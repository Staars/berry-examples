class NC # NVS Constants
    static page_size = 4096
    static entry_size = 32

    static item_type = {
        0x01: 'uint8_t',
        0x11: 'int8_t',
        0x02: 'uint16_t',
        0x12: 'int16_t',
        0x04: 'uint32_t',
        0x14: 'int32_t',
        0x08: 'uint64_t',
        0x18: 'int64_t',
        0x21: 'string',
        0x41: 'blob',
        0x42: 'blob_data',
        0x48: 'blob_index',
    }

    # ESP-IDF PageState values (see nvs_page.hpp)
    static page_status = {
        0xFFFFFFFF: 'Empty',
        0xFFFFFFFE: 'Active',
        0xFFFFFFFC: 'Full',
        0xFFFFFFF8: 'Erasing',     # FREEING
        0xFFFFFFF0: 'Corrupted',   # CORRUPT (NOT 0x00000000)
    }

    static entry_status = {
        3: 'Empty',   # 0b11
        2: 'Written', # 0b10
        0: 'Erased',  # 0b00
    }
end

class NVS_Entry
    var buf, offset, state, is_empty, index, metadata, key, data, type
    var payload_offset, payload_length

    def raw()
        return self.buf[self.offset .. self.offset + NC.entry_size - 1]
    end

    def raw_payload()
        if self.payload_length > 0
            return self.buf[self.payload_offset .. self.payload_offset + self.payload_length - 1]
        end
        return bytes()
    end

    def init(index, partition_bytes, entry_offset, entry_state)
        self.buf = partition_bytes
        self.offset = entry_offset
        self.state = entry_state
        self.is_empty = true
        self.index = index
        self.key = nil
        self.data = nil
        self.payload_offset = 0
        self.payload_length = 0
        self.metadata = {
            "namespace": 0,
            "type": nil,
            "span": 0,
            "chunk_index": 0,
            "crc": {
                "original": 0,
                "computed": 0,
                "data_original": 0,
                "data_computed": 0,
            },
        }

        # Detect empty entry
        var i = 0
        while i < NC.entry_size
            if self.buf[self.offset + i] != 0xFF
                self.is_empty = false
                break
            end
            i += 1
        end

        if !self.is_empty
            var namespace = self.buf[self.offset + 0]
            var entry_type = self.buf[self.offset + 1]
            var span = self.buf[self.offset + 2]
            var chunk_index = self.buf[self.offset + 3]
            var crc_val = self.buf[self.offset + 4 .. self.offset + 7]
            var key_bytes = self.buf[self.offset + 8 .. self.offset + 23]
            var data_bytes = self.buf[self.offset + 24 .. self.offset + 31]
            var raw_without_crc = self.buf[self.offset + 0 .. self.offset + 3] + self.buf[self.offset + 8 .. self.offset + 31]
            self.type = NC.item_type.find(entry_type, f"0x{entry_type:02x}")

            import crc
            self.metadata = {
                "namespace": namespace,
                "type": self.type,
                "span": span,
                "chunk_index": chunk_index,
                "crc": {
                    "original": crc_val.get(0, 4),
                    "computed": crc.crc32(0xFFFFFFFF, raw_without_crc),
                    "data_original": data_bytes[-4 ..].get(0, 4),
                    "data_computed": 0,
                },
            }

            self.key = self.key_decode(key_bytes)
            if self.key != nil
                self.data = self.item_convert(entry_type, data_bytes)
            end

            # For multi-span entries, record payload range (zero-copy)
            if span > 1
                self.payload_offset = self.offset + NC.entry_size
                self.payload_length = (span - 1) * NC.entry_size
            end
        end
    end

    def item_convert(i_type, data)
        var byte_size_mask = 0x0F
        var number_sign_mask = 0xF0
        var fixed_entry_length_threshold = 0x20

        if NC.item_type.find(i_type) != nil
            if i_type < fixed_entry_length_threshold
                var sz = i_type & byte_size_mask
                var num
                try
                    num = data.get(0, sz)
                except ..
                    log("NVS: Corrupt entry!!!")
                    return {"value": nil}
                end
                if (i_type & number_sign_mask) != 0
                    var bits = 8 * sz
                    var signbit = 1 << (bits - 1)
                    var full = 1 << bits
                    if num & signbit != 0
                        num = num - full
                    end
                end
                return {"value": num}
            elif i_type == 0x48
                # blob_index: [total_size:4][chunk_count:1][chunk_start:1][reserved:2]
                var sz = data.get(0, 4)
                var chunk_count = data[4]
                var chunk_start = data[5]
                return {
                    "value": [sz, chunk_count, chunk_start],
                    "size": sz,
                    "chunk_count": chunk_count,
                    "chunk_start": chunk_start
                }
            elif i_type == 0x21 || i_type == 0x41 || i_type == 0x42
                # string / blob_legacy / blob_data: [size:2][reserved:2][data_crc32:4]
                var sz = data.get(0, 2)
                var crc_val = data.get(4, 4)
                return {"value": [sz, crc_val], "size": sz, "crc": crc_val}
            end
        end
        return {"value": nil}
    end

    def key_decode(data)
        var start = 0
        while start < size(data) && data[start] == 0x00
            start += 1
        end
        if start >= size(data)
            return nil
        end

        var decoded = ""
        var i = start
        while i < size(data)
            var b = data[i]
            if b == 0x00
                break
            end
            if b < 128
                decoded += data[i .. i].asstring()
            else
                return nil
            end
            i += 1
        end

        if size(decoded) == 0
            return nil
        end
        return decoded
    end

    # Compute the CRC32 of the variable-length payload.
    # Applies to types: string (0x21), blob_legacy (0x41), blob_data (0x42).
    # blob_index (0x48) has no variable payload — only metadata in the header.
    # The expected CRC ('data_original') was already extracted from the entry
    # header in init() (offset 28..32 of the data field) and must NOT be
    # overwritten here.
    def compute_crc()
        import crc

        var t = self.metadata["type"]
        var written = (self.state == "Written")
        var has_size = self.data != nil && self.data.contains("size") && self.data["size"] != nil

        if !written || !has_size
            self.metadata["crc"]["data_computed"] = 0
            return
        end

        var has_payload = (t == "string") || (t == "blob_legacy") || (t == "blob") || (t == "blob_data")

        if !has_payload || self.payload_length <= 0
            self.metadata["crc"]["data_computed"] = 0
            return
        end

        var size_bytes = self.data["size"]
        var to_hash = size_bytes
        if to_hash > self.payload_length
            to_hash = self.payload_length
        end

        # Stream the payload through CRC in chunks to keep peak RAM low
        var seed = 0xFFFFFFFF
        var pos = self.payload_offset
        var remaining = to_hash
        var chunk = 256
        while remaining > 0
            var take = remaining > chunk ? chunk : remaining
            seed = crc.crc32(seed, self.buf[pos .. pos + take - 1])
            pos += take
            remaining -= take
        end
        self.metadata["crc"]["data_computed"] = seed
    end

    def is_blob()
        var t = self.metadata["type"]
        return self.state == "Written" && (t == "blob" || t == "blob_index")
    end

    def is_blob_data()
        var t = self.metadata["type"]
        return self.state == "Written" && (t == "blob_data")
    end

    def blob_key()
        return self.key
    end

    def blob_total_size()
        if self.data != nil && self.data.contains("size") && self.data["size"] != nil
            return self.data["size"]
        end
        return 0
    end

    def blob_expected_chunks()
        if self.data != nil && self.data.contains("chunk_count") && self.data["chunk_count"] != nil
            return self.data["chunk_count"]
        end
        return 0
    end
end

class NVS_Blob
    var key
    var namespace_idx     # numeric NVS namespace index (qualifies the blob)
    var namespace_name    # resolved later by the inspector (may be nil)
    var total_size
    var expected_chunks
    var chunk_start       # starting chunk index from blob_index (default 0)
    var index_entry
    var chunks   # list of {offset, length, index} -- raw, unfiltered
    var np       # reference to parent NP for access to partition_data

    def init(np, k, ns_idx, total_sz, expected, chunk_start)
        self.np = np
        self.key = k
        self.namespace_idx = ns_idx
        self.namespace_name = nil
        self.total_size = total_sz
        self.expected_chunks = expected
        self.chunk_start = chunk_start != nil ? chunk_start : 0
        self.index_entry = nil
        self.chunks = []
    end

    # Filter chunks to those that belong to the *current* generation
    # (i.e. chunk index in [chunk_start, chunk_start + expected_chunks)).
    # Mirrors NVSEditor.buildChunks() in js/nvs-editor.js.
    def _filtered_chunks()
        if self.expected_chunks == nil || self.expected_chunks <= 0
            return self.chunks
        end
        var result = []
        var start = self.chunk_start != nil ? self.chunk_start : 0
        var ec = self.expected_chunks
        var i = 0
        while i < size(self.chunks)
            var ch = self.chunks[i]
            var rel = ch["index"] - start
            if rel >= 0 && rel < ec
                result.push(ch)
            end
            i += 1
        end
        return result
    end

    # Number of *valid* chunks present (after generation filtering)
    def chunk_count_present()
        return size(self._filtered_chunks())
    end

    # Return the fully assembled blob by reading from partition_data
    def get_data()
        var chunks = self._filtered_chunks()

        # Simple bubble sort by "index" (Berry has no lambda sort)
        var n = chunks.size()
        var swapped = true
        while swapped
            swapped = false
            var i = 0
            while i < n - 1
                if chunks[i]["index"] > chunks[i + 1]["index"]
                    var tmp = chunks[i]
                    chunks[i] = chunks[i + 1]
                    chunks[i + 1] = tmp
                    swapped = true
                end
                i += 1
            end
            n -= 1
        end

        # Append each chunk's bytes from the shared buffer
        var buf = bytes()
        var ci = 0
        while ci < chunks.size()
            var ch = chunks[ci]
            buf = buf .. self.np.partition_data[ch["offset"] .. ch["offset"] + ch["length"] - 1]
            ci += 1
        end
        return buf
    end

    # Store only offset/length/index, no payload allocation here
    def add_chunk_ref(offset, length, index)
        self.chunks.push({
            "offset": offset,
            "length": length,
            "index": index
        })
    end

    def set_index(entry)
        self.index_entry = entry
    end

    # Namespace-qualified id, mirroring NVSEditor.getQualifiedBlobId()
    def qualified_id()
        var ns = self.namespace_name != nil ? self.namespace_name : f"ns_{self.namespace_idx}"
        return f"{ns}::{self.key}"
    end
end

class NVS_Page
    var np, offset
    var is_empty, header, entries

    def init(np, page_offset)
        self.np = np
        self.offset = page_offset
        self.entries = []

        # Detect if page is all 0xFF
        var empty = true
        var i = 0
        while i < NC.page_size
            if self.np.partition_data[self.offset + i] != 0xFF
                empty = false
                break
            end
            i += 1
        end
        self.is_empty = empty

        # Parse header
        import crc
        var buf = self.np.partition_data
        self.header = {
            "status": NC.page_status.find(buf.get(self.offset + 0, 4), "Invalid"),
            "page_index": buf.get(self.offset + 4, 4),
            "version": 256 - buf[self.offset + 8],
            "crc": {
                "original": buf.get(self.offset + 28, 4),
                "computed": crc.crc32(0xFFFFFFFF, buf[self.offset + 4 .. self.offset + 27]),
            },
        }
        if self.is_empty
            self.header["crc"]["original"] = nil
            self.header["crc"]["computed"] = nil
            return
        end

        # Entry state bitmap (entry #1)
        var entry_states = []
        var map_off = self.offset + NC.entry_size
        var j = 0
        while j < NC.entry_size
            var byte = buf[map_off + j]
            var shift = 0
            while shift < 8
                var status = NC.entry_status.find((byte >> shift) & 3, "Invalid")
                entry_states.push(status)
                shift += 2
            end
            j += 1
        end
        entry_states = entry_states[0 .. 125]  # entries 2..127

        # Parse entries
        var entry_count = int(NC.page_size / NC.entry_size)
        i = 2
        while i < entry_count
            var entry_off = self.offset + (i * NC.entry_size)
            var span_byte = buf[entry_off + 2]
            var span = ([0xFF, 0].find(span_byte) != nil) ? 1 : span_byte

            var entry_state = entry_states[i - 2]
            var entry = NVS_Entry(i - 2, buf, entry_off, entry_state)
            self.entries.push(entry)

            # Compute payload CRC32 for variable-length entries (string / blob / blob_data).
            # Cheap: only runs when state == "Written" and the entry has a payload.
            if entry.state == "Written"
                entry.compute_crc()
            end

            # Blob header/index: ensure blob object exists and update totals if needed.
            # Blob ids are namespace-qualified (mirrors NVSEditor.getQualifiedBlobId)
            # so two namespaces can hold a blob with the same key without colliding.
            if entry.is_blob() && entry.key != nil
                self.report_blob(entry)
                # Inline blob payload inside 'blob' header (small blobs): store as a chunk ref
                if entry.metadata["type"] == "blob" && entry.state == "Written"
                    var qid = self.qualified_id(entry.metadata["namespace"], entry.key)
                    if self.np.blob_map.contains(qid)
                        var blob = self.np.blob_map[qid]
                        var chunk_size = entry.data && entry.data["size"] != nil ? entry.data["size"] : 0
                        if chunk_size > 0
                            var inline_off = entry_off + 24
                            var inline_len = chunk_size
                            blob.add_chunk_ref(inline_off, inline_len, 0)
                        end
                    end
                end
            end

            # Blob data: always register chunk refs zero-copy, creating blob if missing
            if entry.is_blob_data() && entry.state == "Written" && entry.key != nil
                var ns_idx = entry.metadata["namespace"]
                var qid = self.qualified_id(ns_idx, entry.key)
                # Ensure blob exists (if header/index not parsed yet, create provisional)
                if !self.np.blob_map.contains(qid)
                    var provisional_total = entry.blob_total_size()  # for blob_data this is chunk size; may be updated later
                    var provisional_chunks = entry.blob_expected_chunks()  # likely 0 for blob_data; updated by blob_index later
                    var new_blob = NVS_Blob(self.np, entry.key, ns_idx, provisional_total, provisional_chunks, 0)
                    self.np.blobs.push(new_blob)
                    self.np.blob_map[qid] = new_blob
                end

                var blob2 = self.np.blob_map[qid]
                # Compute payload range: (span - 1) payload entries, each NC.entry_size bytes
                var payload_offset = entry_off + NC.entry_size
                var payload_length = (span - 1) * NC.entry_size
                # Clamp to declared size in header for this chunk (avoid trailing padding)
                if entry.data && entry.data["size"] != nil && entry.data["size"] < payload_length
                    payload_length = entry.data["size"]
                end
                var chunk_index = entry.metadata["chunk_index"] & 127
                if payload_length > 0
                    # Filtering by [chunk_start, chunk_start + expected_chunks) is
                    # done lazily in NVS_Blob._filtered_chunks() because the
                    # blob_index entry might be parsed AFTER the blob_data chunks.
                    blob2.add_chunk_ref(payload_offset, payload_length, chunk_index)
                end
            end

            i += span
        end
    end

    # Build a namespace-qualified blob id.
    # Mirrors NVSEditor.getQualifiedBlobId() in js/nvs-editor.js.
    def qualified_id(ns_idx, key)
        return f"ns_{ns_idx}::{key}"
    end

    def report_blob(entry)
        var ns_idx = entry.metadata["namespace"]
        var key = entry.blob_key()
        var qid = self.qualified_id(ns_idx, key)
        var new_total = entry.blob_total_size()
        var new_expected = entry.blob_expected_chunks()
        # blob_index entries carry the chunk_start; legacy blob/blob_data don't.
        var new_chunk_start = (entry.data != nil && entry.data.contains("chunk_start") && entry.data["chunk_start"] != nil) ? entry.data["chunk_start"] : nil

        if self.np.blob_map.contains(qid)
            # Update totals if header/index provides better information
            var existing = self.np.blob_map[qid]
            if new_total != nil && new_total > 0
                existing.total_size = new_total
            end
            if new_expected != nil && new_expected > 0
                existing.expected_chunks = new_expected
            end
            if new_chunk_start != nil
                existing.chunk_start = new_chunk_start
            end
            if entry.metadata["type"] == "blob_index"
                existing.set_index(entry)
            end
            return
        end

        # Create blob using header/index info
        var blob = NVS_Blob(self.np, key, ns_idx, new_total, new_expected, new_chunk_start)
        if entry.metadata["type"] == "blob_index"
            blob.set_index(entry)
        end
        self.np.blobs.push(blob)
        self.np.blob_map[qid] = blob
    end
end


# Define the NP class (NVS Partition)
class NP
    var name
    var partition_data
    var blobs
    var blob_map

    def init(name, partition_bytes)
        self.name = name
        self.partition_data = partition_bytes
        self.blobs = []
        self.blob_map = {}
        # no pages[] list here — we will create NVS_Page objects as needed
    end

    # Optional helper to get page count without building page objects
    def page_count()
        return int(size(self.partition_data) / NC.page_size)
    end
end


class NVSInspector
    var loglevel
    var nvs
    var namespaces
    var page_index
    var phase
    var active
    var total_pages
    var nvs_slot_start
    var nvs_slot_size
    var stats

    def init()
        self.loglevel = 1
        self.namespaces = {}
        self.page_index = 0
        self.phase = 0
        self.active = false
        self.total_pages = 0
        self.nvs_slot_start = nil
        self.nvs_slot_size = nil
        self.stats = self._new_stats()
        print(tasmota.memory())
        tasmota.log("NVSInspector loaded. Use 'n <level>' to run.")
    end

    static def _new_stats()
        return {
            "pages_total": 0,
            "pages_active": 0,
            "pages_full": 0,
            "pages_empty": 0,
            "pages_erasing": 0,
            "pages_corrupted": 0,
            "pages_bad_header_crc": 0,
            "entries_written": 0,
            "entries_erased": 0,
            "entries_empty": 0,
            "entries_bad_header_crc": 0,
            "entries_bad_data_crc": 0,
            "blobs_incomplete": 0,
            "blobs_complete": 0,
        }
    end

    def stop()
        tasmota.remove_driver(self)
    end

    # Locate the NVS slot once and cache its (start, size).
    # We avoid using partition_core.Partition() because its init() also
    # invokes load_otadata() which performs additional native flash reads
    # that have been observed to fault on some boards/layouts. We only
    # need the partition table, so we parse it directly here.
    def _find_nvs_slot()
        if self.nvs_slot_start != nil && self.nvs_slot_size != nil
            return true
        end
        import flash
        var raw
        try
            raw = flash.read(0x8000, 0x1000)
        except .. as e, m
            log(f"NVS: [ERROR] Failed to read partition table: {e} {m}")
            return false
        end
        var i = 0
        while i < 95
            var off = i * 32
            var magic = raw.get(off, 2)
            if magic == 0x50AA
                # type(1) + subtype(1) + offset(4) + size(4) + label(16) + flags(4) = 30 bytes after magic
                var p_start = raw.get(off + 4, 4)
                var p_size = raw.get(off + 8, 4)
                # label is 16 bytes, NUL-terminated, ASCII
                var label_bytes = raw[off + 12 .. off + 27]
                var label = ""
                var j = 0
                while j < 16
                    var b = label_bytes[j]
                    if b == 0  break  end
                    label += label_bytes[j .. j].asstring()
                    j += 1
                end
                if label == "nvs"
                    self.nvs_slot_start = p_start
                    self.nvs_slot_size = p_size
                    return true
                end
            elif magic == 0xEBEB
                break
            else
                break
            end
            i += 1
        end
        log("NVS: [ERROR] No 'nvs' partition found in partition table")
        return false
    end

    def read_nvs_partition(bin_to_file)
        import flash

        if !self._find_nvs_slot()
            return nil
        end

        var nvs = nil

        log("NVS: will read NVS partition ...")
        var start_ms = tasmota.millis()

        var nvs_partition
        try
            nvs_partition = flash.read(self.nvs_slot_start, self.nvs_slot_size)
        except .. as e, m
            log(f"NVS: [ERROR] flash.read failed: {e} {m}")
            return nil
        end

        var elapsed = tasmota.millis() - start_ms
        var part_bytes = size(nvs_partition)
        log(f"NVS: flash read took {elapsed} ms for {part_bytes} bytes")
        if part_bytes < 12288
            log(f"NVS: [WARN] Partition size {part_bytes} bytes is smaller than 12 KiB — may be invalid.")
        end
        if part_bytes % 4096 != 0
            log(f"NVS: [WARN] Partition size {part_bytes} bytes is not a multiple of 4 KiB — may be misaligned.")
        end

        if bin_to_file
            var f = open("nvs.bin", "wb")
            if f != nil
                f.write(nvs_partition)
                f.close()
                log("NVS: raw partition dumped to nvs.bin")
            else
                log("NVS: [ERROR] Failed to open nvs.bin for writing")
            end
        else
            nvs = NP("N", nvs_partition)
        end
        return nvs
    end

    def every_100ms()
        if !self.active
            return
        end

        if self.phase == 0
            self.namespaces = {}
            self.page_index = 0
            # streaming-friendly: compute page count from raw partition bytes
            var part_bytes = size(self.nvs.partition_data)
            self.total_pages = int(part_bytes / NC.page_size)

            # loglevel 0: run the same parse + integrity pipeline synchronously,
            # but suppress per-page printing (handled by loglevel guards in
            # _process_page / _process_entry). This still validates page and
            # entry CRCs and reports any corruption.
            if self.loglevel == 0
                var pi = 0
                while pi < self.total_pages
                    var page_off = pi * NC.page_size
                    var page = NVS_Page(self.nvs, page_off)
                    self._process_page(page, 0, self.namespaces)
                    page.entries = nil
                    pi += 1
                end
                self._print_integrity(0)
                self.active = false
                tasmota.gc()
                return
            end

            self.phase = 1
            tasmota.gc()
            return
        end

        if self.phase == 1
            if self.page_index < self.total_pages
                var page_off = self.page_index * NC.page_size
                var page = NVS_Page(self.nvs, page_off)
                self._process_page(page, self.loglevel, self.namespaces)
                self.page_index += 1
            else
                self.phase = 2
                tasmota.gc()
            end
            return
        end

        if self.phase == 2
            self._print_summary(self.namespaces, self.nvs.blobs, self.loglevel)
            self.active = false
            self.phase = 0
            tasmota.log("NVSInspector: Dump complete")
            tasmota.gc()
            print(tasmota.memory())
        end
    end

    def hexdump(data)
        var result = ""
        var offset = 0
        var width = 16

        while offset < size(data)
            var hexline = ""
            var i = 0
            while i < width
                if offset + i < size(data)
                    var byte = data[offset + i]
                    hexline += f"{byte:02X} "
                else
                    hexline += "   "
                end
                i += 1
            end

            var raw = data[offset .. offset + width - 1]
            var j = 0
            while j < size(raw)
                var b = raw[j]
                if b < 32 || b > 126
                    raw[j] = 46
                end
                j += 1
            end
            var asciiline = raw.asstring()
            result += f"{offset:6X}  {hexline}\t {asciiline} \n"
            offset += width
        end
        return result
    end

    def _process_page(page, loglevel, namespaces)
        # Aggregate page-level stats
        self.stats["pages_total"] += 1
        if page.header == nil
            self.stats["pages_corrupted"] += 1
        else
            var st = page.header["status"]
            if st == "Empty"      self.stats["pages_empty"] += 1
            elif st == "Active"   self.stats["pages_active"] += 1
            elif st == "Full"     self.stats["pages_full"] += 1
            elif st == "Erasing"  self.stats["pages_erasing"] += 1
            elif st == "Corrupted" self.stats["pages_corrupted"] += 1
            end
            if !page.is_empty && page.header["crc"]["computed"] != page.header["crc"]["original"]
                self.stats["pages_bad_header_crc"] += 1
            end
        end

        if loglevel == 1 && page.is_empty
            return
        end

        if loglevel >= 1
            print(f"\nPage {page.header['page_index']} - {page.header['status']}")
            if loglevel >= 2
                var hdr_crc_ok = page.header["crc"]["computed"] == page.header["crc"]["original"] ? "OK" : "BAD"
                print(f"  Version: {page.header['version']} Header CRC: {hdr_crc_ok}")
            end
        end

        var ei = 0
        while ei < size(page.entries)
            var entry = page.entries[ei]
            self._process_entry(entry, page, loglevel, namespaces)
            page.entries[ei] = nil
            ei += 1
        end
        page.entries = nil
    end

    def _process_entry(entry, page, loglevel, namespaces)
        # Aggregate entry-level stats (count regardless of loglevel filter)
        if entry.is_empty
            self.stats["entries_empty"] += 1
            return
        end
        if entry.state == "Written"
            self.stats["entries_written"] += 1
        elif entry.state == "Erased"
            self.stats["entries_erased"] += 1
        end
        # Header CRC: only meaningful for non-empty entries with computed CRC
        if entry.metadata["crc"]["computed"] != entry.metadata["crc"]["original"]
            self.stats["entries_bad_header_crc"] += 1
        end
        # Data CRC: only meaningful when compute_crc actually produced a value
        var dc = entry.metadata["crc"]["data_computed"]
        if dc != 0 && dc != entry.metadata["crc"]["data_original"]
            self.stats["entries_bad_data_crc"] += 1
        end

        if entry.key == nil
            return
        end

        var ns = entry.metadata["namespace"]
        self._collect_namespaces(entry, namespaces)

        if loglevel < 1
            return
        end
        if loglevel == 1 && entry.state != "Written"
            return
        end

        # Resolve namespace index to name if known so far
        var ns_label = namespaces.find(ns, str(ns))

        # Header CRC indicator
        var hdr_ok = entry.metadata["crc"]["computed"] == entry.metadata["crc"]["original"] ? "OK" : "BAD"
        var type_str = entry.metadata["type"] != nil ? entry.metadata["type"] : "?"

        var line = f"   #{entry.index}\tKey: {entry.key:16s}  Type: {type_str}\tNS:{ns}({ns_label})\tState: {entry.state}\tHdr:{hdr_ok}"
        if loglevel >= 2 && entry.metadata["crc"]["data_computed"] != 0
            var crc_ok = entry.metadata["crc"]["data_computed"] == entry.metadata["crc"]["data_original"] ? "OK" : "FAIL"
            line += f"\tData:{crc_ok}"
        end
        print(line)

        if loglevel >= 3
            # Print incrementally to avoid building large strings on a tight heap.
            # Coerce values via str() so any nil/odd type prints safely.
            print("     RAW: " + str(entry.raw()))
            print("     META: " + str(entry.metadata))
            print("     DATA: " + str(entry.data))
            tasmota.gc()
        end
    end

    def _collect_namespaces(entry, namespaces)
        # Only record live (Written) namespace definitions, with valid string keys
        if entry.state != "Written"  return  end
        if entry.metadata["namespace"] != 0  return  end
        if entry.metadata["type"] != "uint8_t"  return  end
        if entry.key == nil  return  end
        if entry.data == nil || entry.data["value"] == nil  return  end
        namespaces[entry.data["value"]] = entry.key
    end

    # Resolve namespace_name on each blob from collected namespace map.
    # Done here rather than at parse time because namespace defs may be parsed
    # AFTER blobs in different pages.
    def _resolve_blob_namespaces(blobs, namespaces)
        var i = 0
        while i < size(blobs)
            var b = blobs[i]
            if b.namespace_name == nil && b.namespace_idx != nil
                b.namespace_name = namespaces.find(b.namespace_idx, nil)
            end
            i += 1
        end
    end

    # Check blob completeness for stats. Returns nothing (just updates self.stats).
    # Uses the *filtered* chunk count (matches NVSEditor.checkBlobIntegrity).
    def _check_blob_integrity(blobs)
        var i = 0
        while i < size(blobs)
            var b = blobs[i]
            var present = b.chunk_count_present()
            var expected = b.expected_chunks != nil ? b.expected_chunks : 0
            if expected > 0
                if present >= expected
                    self.stats["blobs_complete"] += 1
                else
                    self.stats["blobs_incomplete"] += 1
                end
            else
                # Legacy/inline blob — no expected chunk count from index
                if present > 0
                    self.stats["blobs_complete"] += 1
                else
                    self.stats["blobs_incomplete"] += 1
                end
            end
            i += 1
        end
    end

    def _print_blobs(blobs, loglevel)
        if size(blobs) > 0
            print("\nBlobs found:")
            var i = 0
            while i < size(blobs)
                var b = blobs[i]
                var qid = b.qualified_id()
                var total = b.total_size != nil ? b.total_size : 0
                var present = b.chunk_count_present()
                var expected = b.expected_chunks != nil ? b.expected_chunks : 0
                var status
                if expected > 0
                    status = present >= expected ? "OK" : f"INCOMPLETE({present}/{expected})"
                else
                    status = present > 0 ? "OK" : "EMPTY"
                end
                print(f"  {qid:24s} TotalSize: {total:8d}\tChunks: {present}/{expected}\t{status}")
                if loglevel > 3
                    var payload = b.get_data()
                    print("  Hexdump:")
                    print(self.hexdump(payload))
                end
                i += 1
                tasmota.gc()
            end
        else
            print("\nNo blob entries found.")
        end
    end

    def _print_integrity(loglevel)
        # Resolve blob namespace names from the namespace map (best effort)
        self._resolve_blob_namespaces(self.nvs.blobs, self.namespaces)
        # Update blob stats once, just before printing
        self._check_blob_integrity(self.nvs.blobs)

        var s = self.stats
        print("\nIntegrity report:")
        print(f"  Pages   total:{s['pages_total']}  active:{s['pages_active']}  full:{s['pages_full']}  empty:{s['pages_empty']}  erasing:{s['pages_erasing']}  corrupted:{s['pages_corrupted']}")
        if s["pages_bad_header_crc"] > 0
            print(f"  Pages with BAD header CRC: {s['pages_bad_header_crc']}")
        end
        print(f"  Entries written:{s['entries_written']}  erased:{s['entries_erased']}  empty:{s['entries_empty']}")
        if s["entries_bad_header_crc"] > 0
            print(f"  Entries with BAD header CRC: {s['entries_bad_header_crc']}")
        end
        if s["entries_bad_data_crc"] > 0
            print(f"  Entries with BAD data   CRC: {s['entries_bad_data_crc']}")
        end
        print(f"  Blobs   complete:{s['blobs_complete']}  incomplete:{s['blobs_incomplete']}")
        var ok = (s["entries_bad_header_crc"] == 0) && (s["entries_bad_data_crc"] == 0) && (s["pages_bad_header_crc"] == 0) && (s["pages_corrupted"] == 0) && (s["blobs_incomplete"] == 0)
        if ok
            print("  NVS integrity: OK")
        else
            print("  NVS integrity: ISSUES DETECTED")
        end
    end

    def _print_summary(namespaces, blobs, loglevel)
        # Resolve blob namespace names so qualified ids print as 'wifi::config'
        # rather than 'ns_3::config'. (Mirrors NVSEditor's qualified blob id.)
        self._resolve_blob_namespaces(blobs, namespaces)

        if loglevel < 1
            self._print_integrity(loglevel)
            return
        end

        if size(namespaces) > 0
            print("\nNamespaces found:")
            for ns_idx : namespaces.keys()
                print(f"  Index {ns_idx} -> {namespaces[ns_idx]}")
            end
        else
            print("\nNo namespace entries found.")
        end
        self._print_blobs(blobs, loglevel)
        self._print_integrity(loglevel)
    end

    def dump_nvs(loglevel)
        self.active = false
        self.nvs = nil
        tasmota.gc()
        self.loglevel = loglevel
        self.total_pages = 0
        self.stats = self._new_stats()
        tasmota.log(f"NVSInspector: Starting dump with loglevel {loglevel}")
        self.nvs = self.read_nvs_partition(false)
        if self.nvs == nil
            tasmota.log("NVSInspector: No NVS partition found")
            self.active = false
            return
        end
        self.active = true
        self.phase = 0
        self.page_index = 0
    end
end

# Register the driver
var nvs = NVSInspector()
tasmota.add_driver(nvs)

# Command: n <level 0 - 4>
def cmd_n(cmd, idx, payload, payload_json)
  var level = 1
  if payload != ""
    try
      level = int(payload)
    except ..
      tasmota.log("Invalid loglevel, using default 1")
    end
  end
  nvs.dump_nvs(level)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd("n", cmd_n)

# Command: d (dump raw to file: nvs.bin)
def cmd_d(cmd, idx, payload, payload_json)
  nvs.read_nvs_partition(true)
  tasmota.resp_cmnd_done()
end

tasmota.add_cmd("d", cmd_d)
