#- Simple FTP server in Berry by Christian Baars
#  supports active and passive mode - but passive is preferred!
#  only light error handling
-#

#@ solidify:PATH,weak
class PATH    # helper class to hold the current directory
    var p  #  path components in a list

    def init()
        import string
        self.p = []
    end

    def set(p)
        import string
        import path

        if path.isdir(p) != true
            return false
        end

        var new = string.split(p,"/")
        self.p = []
        for c:new
            if c != ""
                self.p.push(c)
            end
        end
        return true
    end

    def dir_up()
        if size(self.p) > 0
            self.p.pop()
        end
    end

    def get_url()
        var url = "/"
        for c:self.p
            if c != ""
                url += f"{c}/"
            end
        end
        return url
    end
end

#@ solidify:FTP,weak
class FTP : Driver

    var connection, server, client, data_server, data_client, data_ip
    var dir, dir_list, dir_pos
    var file, file_size, file_rename, retries, chunk_size
    var binary_mode, active_ip, active_port, user_input
    var data_buf, data_ptr, fast_loop, data_op
    var cmd_buf                                       # incoming control bytes pending newline
    var data_pending_cb, data_pending_deadline        # async data connection setup
    static port = 21
    static data_port = 20         # data connection in passive mode
    static allow_anonymous = true # allow everything ..
    static user = "user"
    static password = "pass"
    static data_timeout_ms = 5000 # how long to wait for data connection setup

    def init()
        self.server = tcpserver(self.port) # connection for control data
        self.connection = false
        self.data_ip = tasmota.wifi()['ip']
        self.dir = PATH()
        self.readDir()
        self.fast_loop = nil
        self.data_client = nil
        self.data_server = nil
        self.reset_session()
        tasmota.add_driver(self)
        log(f"FTP: init server on port {self.port}",1)
    end

    # reset all per-session state, called on every new control connection
    def reset_session()
        self.data_ptr = 0
        self.binary_mode = true
        self.active_port = nil
        self.active_ip = nil
        self.file = nil
        self.file_rename = nil
        self.user_input = nil
        self.cmd_buf = ""
        self.data_op = nil
        self.data_pending_cb = nil
        self.data_pending_deadline = 0
    end

    def deinit()
        if self.fast_loop != nil
            tasmota.remove_fast_loop(self.fast_loop)
            self.fast_loop = nil
        end
        if self.server != nil
            self.server.deinit()
        end
        if self.data_server != nil
            self.data_server.deinit()
            self.data_server = nil
        end
        if self.data_client != nil
            self.data_client.close()
            self.data_client.deinit()
            self.data_client = nil
        end
        tasmota.remove_driver(self)
    end

    def every_50ms()
        if self.connection == true
            self.loop()
            # politely refuse a second concurrent client
            if self.server.hasclient()
                var c = self.server.acceptasync()
                if c != nil
                    c.write("421 Service not available, only one client supported\r\n")
                    c.close()
                    c.deinit()
                end
            end
        elif self.server.hasclient()
            self.client = self.server.acceptasync()
            self.reset_session()
            self.sendResponse("220 Welcome")
            self.connection = true
            self.pubClientInfo()
        end
    end

    def every_second()
        if self.client && self.connection != false
            if self.client.connected() == false
                self.pubClientInfo()
                self.connection = false
                self.abortDataOp()
            end
        end
        # keep data_ip up to date in case of WiFi reconnect / DHCP renew
        var ip = tasmota.wifi()['ip']
        if ip != nil && ip != "" && ip != "0.0.0.0"
            self.data_ip = ip
        end
    end

    def pubClientInfo()
        import mqtt
        var payload = self.client.info().tostring()
        mqtt.publish("FTP",format("{'server':%s}", payload))
    end

    def loop()
        if self.connection == true
            self.handleConnection()
        end
    end

    def abortDataOp()
        # if we are still waiting for a data connection to be established,
        # cancel that pending op cleanly
        if self.data_pending_cb != nil
            self.data_pending_cb = nil
            if self.fast_loop != nil
                tasmota.remove_fast_loop(self.fast_loop)
                self.fast_loop = nil
            end
            if self.data_client != nil
                self.data_client.close()
                self.data_client.deinit()
                self.data_client = nil
            end
            return
        end
        if self.data_op == "d"
            self.finishDownload(true)
        elif self.data_op == "u"
            self.finishUpload(true)
        elif self.data_op == "dir"
            self.finishTransferDir(false)
        end
    end

    def download() # ESP -> client
        if self.data_client == nil || self.data_client.connected() == false
            self.finishDownload(true)
            return
        end
        # only read more from disk if we have nothing left to send
        if size(self.data_buf) == 0
            self.data_buf..self.file.readbytes(self.chunk_size)
        end
        if size(self.data_buf) == 0
            # EOF
            self.finishDownload(false)
            return
        end
        var written = self.data_client.write(self.data_buf)
        if written > 0
            self.data_ptr += written
            if written >= size(self.data_buf)
                self.data_buf.clear()
            else
                # keep the un-sent tail for next iteration
                self.data_buf = self.data_buf[written..]
            end
            self.retries = 10  # progress -> reset retry counter
        else
            self.retries -= 1
            if self.retries <= 0
                self.finishDownload(true)
            end
        end
    end

    def finishDownload(error)
        if self.fast_loop != nil
            tasmota.remove_fast_loop(self.fast_loop)
            self.fast_loop = nil
        end
        if self.data_client != nil
            self.data_client.close()
            self.data_client.deinit()
            self.data_client = nil
        end
        if self.file != nil
            self.file.close()
            self.file = nil
        end
        if error
            self.sendResponse(f"426 Connection closed; transfer aborted after {self.data_ptr} bytes.")
        else
            self.sendResponse(f"226 download done with {self.data_ptr} bytes.")
        end
        self.data_op = nil
        self.data_ptr = 0
        tasmota.gc()
    end

    def upload() # client -> ESP
        if self.data_client == nil
            self.finishUpload(true)
            return
        end
        # bounded read to avoid unbounded heap allocation on a fast LAN
        self.data_buf..self.data_client.readbytes(self.chunk_size)

        if size(self.data_buf) > 0
            self.file.write(self.data_buf)
            self.data_ptr += size(self.data_buf)
            self.data_buf.clear()
            self.retries = 10  # progress -> reset retry counter
        else
            log(f"FTP: {self.retries} retries",4)
            self.retries -= 1
            if self.retries <= 0
                # peer closed = normal end-of-file; otherwise treat as error
                if self.data_client.connected() == false
                    self.finishUpload(false)
                else
                    self.finishUpload(true)
                end
            end
        end
    end

    def finishUpload(error)
        if self.fast_loop != nil
            tasmota.remove_fast_loop(self.fast_loop)
            self.fast_loop = nil
        end
        if self.data_client != nil
            self.data_client.close()
            self.data_client.deinit()
            self.data_client = nil
        end
        if self.file != nil
            self.file.close()
            self.file = nil
        end
        if error
            self.sendResponse(f"426 Connection closed; transfer after {self.data_ptr} bytes")
        else
            self.sendResponse(f"226 upload done with {self.data_ptr} bytes")
        end
        self.data_op = nil
        self.data_ptr = 0
        tasmota.gc()
    end

    def transferDir(mode)
        import path
        var sz, date, isdir
        var i = self.dir_list[self.dir_pos]
        var url = f"{self.dir.get_url()}{i}"
        isdir = path.isdir(url)
        if isdir == false
            var f = open(url,"r")
            sz = f.size()
            f.close()
            date = path.last_modified(url)
        end
        if self.data_client.connected()
            var dir = ""
            if mode == "MLSD"
                if  isdir
                    dir = "Type=dir;Perm=edlmp; "
                else
                    date = tasmota.time_dump(date)
                    var y = str(date['year'])
                    var m = f"{date['month']:02s}"
                    var d = f"{date['day']:02s}"
                    var h = f"{date['hour']:02s}"
                    var min = f"{date['min']:02s}"
                    var sec = f"{date['sec']:02s}"
                    var modif =f"{y}{m}{d}{h}{min}{sec}"
                    dir = f"Type=file;Perm=rwd;Modify={modif};Size={sz}; "
                end
            elif mode == "LIST"
                var d = "-"
                if isdir
                    d = "d"
                    date = ""
                    sz = ""
                else
                    date = tasmota.strftime("%b %d %H:%M", date)
                end
                dir = f"{d}rw-------  1 all all{sz:14s} {date} "

            elif mode == "NLST"
                dir=self.dir.get_url()
            end
            var entry = f"{dir}{i}"
            log(entry,4)
            self.data_client.write(entry + "\r\n")
            self.dir_pos += 1
        else
            self.finishTransferDir(false)
            return
        end
        if self.dir_pos < size(self.dir_list)
            return
        end
        self.finishTransferDir(true)
    end

    def finishTransferDir(success)
        if self.fast_loop != nil
            tasmota.remove_fast_loop(self.fast_loop)
            self.fast_loop = nil
        end
        if self.data_client != nil
            self.data_client.close()
            self.data_client.deinit()
            self.data_client = nil
        end
        if success
            var n = size(self.dir_list)
            self.sendResponse(f"226 {n} files in {self.dir.get_url()}")
        else
            self.sendResponse("426 Transfer aborted")
        end
        self.data_op = nil
        tasmota.gc()
    end

    def readDir()
        import path
        self.dir_list = path.listdir(self.dir.get_url())
    end

    # very small path-safety helper; rejects path traversal and backslashes
    def is_safe_arg(arg)
        import string
        if arg == nil || arg == "" return false end
        if string.find(arg, "..") >= 0 return false end
        if string.find(arg, "\\") >= 0 return false end
        return true
    end

    def openFile(name,mode)
        import path
        var url = f"{self.dir.get_url()}{name}"
        if path.isdir(url) == true
            log(f"FTP: {url} is a folder",2)
            return false
        end
        if mode == "r"
            if path.exists(url) != true
                log(f"FTP: {url} not found",2)
                return false
            end
        end
        log(f"FTP: Open file {url} in {mode} mode",3)
        self.file = open(f"{url}",mode)
        if mode == "a"
            if self.data_ptr != 0
                log(f"FTP: Appending file {url} at position {self.data_ptr}",3)
                if self.data_ptr != self.file.size()
                    log(f"FTP: !!! resume position of {self.data_ptr} != file size of {self.file.size()} !!!",2)
                end
            end
        end
        return true
    end

    def close()
        self.sendResponse("221 Closing connection")
        self.connection = false
    end


    def deinitConnectServer()
        if self.data_server != nil
            self.data_server.close()
            self.data_server.deinit()
            self.data_server = nil
            log("FTP: Delete server for passive data connection",2)
        end
    end

    def initConnectServer()
        if self.data_server == nil
            self.data_server = tcpserver(self.data_port)
            log("FTP: Start server for passive data connection",2)
        end
    end

    def connectActive()
        self.data_client = tcpclientasync()
        if self.data_client.connect(self.active_ip,self.active_port) != false
            log(f"FTP: Try to connect to {self.active_ip}:{self.active_port}",3)
        end
    end

    # asynchronous data-connection setup.
    # `op_cb` is invoked once the data connection is ready.
    # In passive mode this waits up to `data_timeout_ms` for the client to
    # connect, instead of failing immediately on a single hasclient() probe.
    def dataconnect_start(op_cb)
        # close any leftover data client first
        if self.data_client != nil
            self.data_client.close()
            self.data_client.deinit()
            self.data_client = nil
        end
        self.data_buf = bytes()
        self.retries = 10
        self.chunk_size = 5760

        if self.active_port != nil
            self.connectActive()
            if self.data_client == nil
                self.sendResponse("425 Data connection failed (active)")
                return false
            end
        else
            if self.data_server == nil
                self.sendResponse("425 No data server (issue PASV/EPSV first)")
                return false
            end
        end

        self.data_pending_cb = op_cb
        self.data_pending_deadline = tasmota.millis(self.data_timeout_ms)
        # avoid leaking a previous fast loop
        if self.fast_loop != nil
            tasmota.remove_fast_loop(self.fast_loop)
        end
        self.fast_loop = /->self.poll_data_ready()
        tasmota.add_fast_loop(self.fast_loop)
        return true
    end

    # polled by fast_loop until the data connection is up or the timeout
    # elapses; then fires the queued op_cb or replies 425.
    def poll_data_ready()
        var ready = false
        if self.active_port != nil
            # active mode: wait for our outgoing connect to complete
            if self.data_client != nil && self.data_client.connected()
                ready = true
            end
        else
            # passive mode: wait for the client to connect to us
            if self.data_client == nil && self.data_server != nil && self.data_server.hasclient()
                self.data_client = self.data_server.acceptasync()
            end
            if self.data_client != nil
                ready = true
            end
        end

        if ready
            tasmota.remove_fast_loop(self.fast_loop)
            self.fast_loop = nil
            var cb = self.data_pending_cb
            self.data_pending_cb = nil
            self.sendResponse("150 Ready for data transfer")
            if cb != nil cb() end
        elif tasmota.time_reached(self.data_pending_deadline)
            tasmota.remove_fast_loop(self.fast_loop)
            self.fast_loop = nil
            self.data_pending_cb = nil
            if self.data_client != nil
                self.data_client.close()
                self.data_client.deinit()
                self.data_client = nil
            end
            self.sendResponse("425 Data connection failed (timeout)")
        end
    end

    # callbacks queued by dataconnect_start, run once data connection is ready

    def begin_upload(fname)
        var mode = "w"
        if self.data_ptr > 0
            mode = "a"
        end
        if self.openFile(fname, mode)
            self.data_op = "u"
            self.fast_loop = /->self.upload()
            tasmota.add_fast_loop(self.fast_loop)
        else
            self.sendResponse("550 Could not open file")
            if self.data_client != nil
                self.data_client.close()
                self.data_client.deinit()
                self.data_client = nil
            end
        end
    end

    def begin_download(fname)
        if self.openFile(fname, "r")
            self.file_size = self.file.size()
            self.data_op = "d"
            self.fast_loop = /->self.download()
            tasmota.add_fast_loop(self.fast_loop)
        else
            self.sendResponse("550 Could not open file")
            if self.data_client != nil
                self.data_client.close()
                self.data_client.deinit()
                self.data_client = nil
            end
        end
    end

    def begin_listdir(mode)
        if size(self.dir_list) > 0
            self.data_op = "dir"
            self.dir_pos = 0
            self.fast_loop = /->self.transferDir(mode)
            tasmota.add_fast_loop(self.fast_loop)
        else
            self.finishTransferDir(true)
        end
    end

    def sendResponse(resp)
        self.client.write(f"{resp}\r\n")
        log(f"FTP: Response: {resp}",3)
    end

    # read whatever is available on the control socket, accumulate into
    # cmd_buf, and process every complete CRLF-terminated line.
    def handleConnection()
        import string
        var d = self.client.read()
        if d == nil || size(d) == 0 return end
        self.cmd_buf = self.cmd_buf + d
        var lines = string.split(self.cmd_buf, "\n")
        # the last element is the (possibly empty) partial trailer
        var n = size(lines)
        self.cmd_buf = lines[n - 1]
        var i = 0
        while i < n - 1
            var line = lines[i]
            var ln = size(line)
            if ln > 0 && line[ln - 1 .. ln - 1] == "\r"
                line = (ln > 1) ? line[0 .. ln - 2] : ""
            end
            if size(line) > 0
                self.process_command(line)
            end
            i += 1
        end
    end

    # main dispatcher for a single FTP command line
    def process_command(line)
        import string
        import mqtt
        import path
        var sp = string.find(line, " ")
        var cmd
        var arg = ""
        if sp < 0
            cmd = line
        else
            cmd = (sp > 0) ? line[0 .. sp - 1] : ""
            if (sp + 1) < size(line)
                arg = line[sp + 1 ..]
            end
        end
        cmd = string.toupper(cmd)
        var response = ""

        log(f"FTP: Received: {cmd} {arg}",3)

        # connect
        if cmd == "USER"
            if self.allow_anonymous
                response = "230 accept any/anonymous user"
            else
                self.user_input = arg
                response = "331 Password required"
            end
        elif cmd == "PASS"
            if self.user_input == self.user && arg == self.password
                response = "230 User accepted"
            else
                response = "530 Wrong login credentials"
                mqtt.publish("FTP","{'login':'wrong credentials'}")
            end
        elif cmd == "AUTH"
            response = f"500 Server does not support {arg}"
        elif cmd == "ABOR"
            self.abortDataOp()
            response = f"200 Aborting"
        elif cmd == "QUIT"
            self.close()
        #options
        elif cmd == "FEAT"
            self.sendResponse("211-Extensions supported:")
            self.sendResponse(" MLSD")
            self.sendResponse(" EPSV")
            self.sendResponse(" SIZE")
            # self.sendResponse(" MDTM")
            self.sendResponse(" REST STREAM")
            response = "211 End"
        elif cmd == "OPTS"
            # accept "UTF8", "UTF8 ON", "UTF8 ON NLST", etc.
            var opt_upper = string.toupper(arg)
            if string.find(opt_upper, "UTF8") == 0
                response = "200 UTF Ok"
            else
                response = f"500 Server does not support {arg}"
            end
        elif cmd == "STRU"
            if arg == "F"
                response = "200 F Ok"
            else
                response = "504 Only F (ile) is supported"
            end
        elif cmd == "SYST"
            response = "215 UNIX"
        elif cmd == "LPRT"
                  response = f"501 active connection with long address not supported"
        elif cmd == "PORT"
            var el = string.split(arg,",")
            self.active_ip = f"{el[0]}.{el[1]}.{el[2]}.{el[3]}"
            self.active_port = int(el[4])*256 + int(el[5])
            response = f"200 port received {self.active_ip}:{self.active_port}"
            self.deinitConnectServer()
            #   response = f"501 active connection not supported"
        elif cmd == "EPRT"
            var el = string.split(arg,"|") # |1|192.168.1.54|65519| -> 1 IPV4, 2 IPV6
            self.active_ip = el[2]
            self.active_port = int(el[3])
            self.deinitConnectServer()
            response = f"200 extended port received {self.active_ip}:{self.active_port}"
        elif cmd == "TYPE"
            if arg == "I"
                response = "200 binary mode"
                self.binary_mode = true
            elif arg == "A"
                response = "200 ascii mode"
                self.binary_mode = false
            end
        elif cmd == "EPSV"
            self.active_port = nil
            # refresh data_ip in case WiFi reconnected since init
            var ip = tasmota.wifi()['ip']
            if ip != nil && ip != "" && ip != "0.0.0.0"
                self.data_ip = ip
            end
            self.initConnectServer()
            response = f"229 Entering Extended Passive Mode (|||{self.data_port}|)"
        elif cmd == "PASV"
            self.active_port = nil
            # refresh data_ip in case WiFi reconnected since init
            var ip = tasmota.wifi()['ip']
            if ip != nil && ip != "" && ip != "0.0.0.0"
                self.data_ip = ip
            end
            var el = string.split(self.data_ip,".")
            var hi = self.data_port >> 8
            var lo = self.data_port & 0xff
            self.initConnectServer()
            response = f"227 Entering passive mode ({el[0]},{el[1]},{el[2]},{el[3]},{hi},{lo})"
        elif cmd == "DELE"
            if !self.is_safe_arg(arg)
                response = "550 Invalid path"
            elif path.remove(f"{self.dir.get_url()}{arg}")
                response = f"250 {self.dir.get_url()}{arg} deleted"
            else
                response = f"550 Could not delete file {self.dir.get_url()}{arg}"
            end
        elif  cmd == "RMD"
            if !self.is_safe_arg(arg)
                response = "550 Invalid path"
            else
                var url = arg
                if arg[0..0] != "/"
                    url = f"{self.dir.get_url()}{arg}"
                end
                if path.rmdir(url)
                    response = f"250 {url} deleted"
                else
                    response = f"550 Could not delete folder {url}"
                end
            end
        elif cmd == "STOR"
            if !self.is_safe_arg(arg)
                response = "550 Invalid path"
            else
                var fname = arg
                self.dataconnect_start(/-> self.begin_upload(fname))
            end
        elif cmd == "REST"
            self.data_ptr = int(arg)
            response = f"350 {self.data_ptr}"
        elif cmd == "RNFR"
            if !self.is_safe_arg(arg)
                response = "550 Invalid path"
                self.file_rename = nil
            elif self.openFile(arg,"r")
                self.file_rename = f"{self.dir.get_url()}{arg}"
                response = f"350 {arg}"
                self.file.close()
                self.file = nil
            else
                self.file_rename = nil
                response = f"550 Could not open file"
            end
        elif cmd == "RNTO"
            # UfsRename uses comma as separator -> reject names containing one
            if self.file_rename != nil && self.is_safe_arg(arg) && string.find(arg, ",") < 0
                tasmota.cmd(f"UfsRename {self.file_rename},{self.dir.get_url()}{arg}")
                response = f"250 Renamed {self.file_rename} -> {arg}"
            else
                response = f"550 Could not rename file"
            end
            self.file_rename = nil
        elif cmd == "SIZE"
            if !self.is_safe_arg(arg)
                response = "550 Invalid path"
            elif self.openFile(arg,"r")
                response = f"213 {self.file.size()}"
                self.file.close()
                self.file = nil
            else
                response = f"550 Could not open file"
            end
        elif cmd == "RETR"
            if !self.is_safe_arg(arg)
                response = "550 Invalid path"
            else
                var fname = arg
                self.dataconnect_start(/-> self.begin_download(fname))
            end
        # folder
        elif cmd == "CDUP"
            self.dir.dir_up()
            response = "250 okay"
        elif cmd == "CWD"
            if self.dir.set(arg)
                response = "250 okay"
            else
                response = "550 Failed to change directory."
            end
        elif cmd == "PWD"
            self.readDir()
            response = f"250 {self.dir.get_url()}"
        elif cmd == "MKD"
            if !self.is_safe_arg(arg)
                response = "550 Invalid path"
            else
                path.mkdir(f"{self.dir.get_url()}{arg}")
                response = f"250 {self.dir.get_url()}{arg} created"
            end
        elif cmd == "LIST" || cmd == "MLSD" || cmd == "NLST"
            if arg != ""
                self.dir.set(arg)
            end
            self.readDir()
            var mode = cmd
            self.dataconnect_start(/-> self.begin_listdir(mode))
        else # any unknown command
            response = "202 Command not implemented in Berry FTP"
        end

        if response != ""
            self.sendResponse(response)
        end
    end
end

# Auto-start when this file is loaded as a runtime driver.
# During host-side solidification `tasmota` is stubbed to nil, which
# short-circuits this branch and prevents FTP.init() from running with
# missing globals.
if tasmota
    var ftp = FTP()
end

return FTP
