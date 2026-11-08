"""Read-only Mach-O metadata and partial Thumb-1 evidence helper.

No execution, modification, build or packaging. --function prints recovered
instructions and PC-relative literals; unsupported instructions remain .hword.
This is a targeted aid for the supplied binary, not a complete disassembler.
"""
import argparse
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


class Reference:
    def __init__(self):
        self.data = (ROOT / 'Payload/Hanoi Plus.app/Hanoi Plus').read_bytes()
        self.sections = []
        self.symbols = {}
        self.stubs = {}
        offset = 28
        for _ in range(struct.unpack_from('<I', self.data, 16)[0]):
            cmd, size = struct.unpack_from('<II', self.data, offset)
            if cmd == 1:
                for i in range(struct.unpack_from('<I', self.data, offset + 48)[0]):
                    pos = offset + 56 + i * 68
                    name = self.data[pos:pos + 16].split(b'\0')[0].decode()
                    addr, length, fileoff = struct.unpack_from('<III', self.data, pos + 32)
                    self.sections.append((name, addr, length, fileoff))
            if cmd == 2:
                symoff, nsyms, stroff, _ = struct.unpack_from('<4I', self.data, offset + 8)
            if cmd == 0xB:
                indirectoff = struct.unpack_from('<I', self.data, offset + 56)[0]
            offset += size
        all_symbols = []
        for i in range(nsyms):
            index, kind, section, desc, value = struct.unpack_from('<IBBHI', self.data, symoff + i * 12)
            name = self.data[stroff + index:].split(b'\0')[0].decode(errors='replace')
            all_symbols.append(name)
            if value and kind & 0xE == 0xE and not kind & 0xE0:
                self.symbols[name] = value
        stub = next(s for s in self.sections if s[0] == '__symbol_stub4')
        for i in range(stub[2] // 12):
            index = struct.unpack_from('<I', self.data, indirectoff + i * 4)[0]
            self.stubs[stub[1] + i * 12] = all_symbols[index]

    def bytes_at(self, addr, size):
        for _, start, length, fileoff in self.sections:
            if start <= addr < start + length:
                return self.data[fileoff + addr - start:fileoff + addr - start + size]
        return b''

    def word(self, addr):
        return struct.unpack('<I', self.bytes_at(addr, 4))[0]

    def description(self, addr):
        names = [name for name, value in self.symbols.items() if value == addr]
        if names:
            return ', '.join(names)
        for name, start, size, _ in self.sections:
            if start <= addr < start + size:
                if name == '__cstring':
                    return repr(self.bytes_at(addr, size).split(b'\0')[0].decode(errors='replace'))
                if name in ('__objc_selrefs', '__objc_classrefs'):
                    return f'{name}: {self.description(self.word(addr))}'
                if name == '__cfstring':
                    return f'CFString: {self.description(self.word(addr + 8))}'
                return f'{name} word=0x{self.word(addr):x}'
        return ''

    def disassemble(self, function):
        start = self.symbols[function]
        end = min(v for v in self.symbols.values() if v > start and v < 17365)
        def signed(v, bits):
            return v - (1 << bits) if v & (1 << (bits - 1)) else v
        addr = start
        pool = end
        while addr < min(end, pool):
            h = struct.unpack('<H', self.bytes_at(addr, 2))[0]
            a, b, c = h & 7, (h >> 3) & 7, (h >> 6) & 7
            text = f'.hword 0x{h:04x}'
            size = 2
            if h >> 11 in (0, 1, 2):
                text = f'{["lsl", "lsr", "asr"][h >> 11]} r{a}, r{b}, #{(h >> 6) & 31}'
            elif h & 0xF800 == 0x1800:
                text = f'{"sub" if h & 512 else "add"} r{a}, r{b}, {"#" if h & 1024 else "r"}{c}'
            elif h & 0xE000 == 0x2000:
                text = f'{["mov", "cmp", "add", "sub"][(h >> 11) & 3]} r{(h >> 8) & 7}, #{h & 255}'
            elif h & 0xFC00 == 0x4000:
                text = f'{["and","eor","lsl","lsr","asr","adc","sbc","ror","tst","neg","cmp","cmn","orr","mul","bic","mvn"][(h >> 6) & 15]} r{a}, r{b}'
            elif h & 0xFC00 == 0x4400:
                text = f'{["add","cmp","mov","bx"][(h >> 8) & 3]} r{a + ((h >> 4) & 8)}, r{(h >> 3) & 15}'
                if (h >> 8) & 3 == 3:
                    text = f'{"blx" if h & 128 else "bx"} r{(h >> 3) & 15}'
            elif h & 0xF800 == 0x4800:
                loc = ((addr + 4) & ~3) + (h & 255) * 4
                pool = min(pool, loc)
                val = self.word(loc)
                flt = struct.unpack('<f', struct.pack('<I', val))[0]
                text = f'ldr r{(h >> 8) & 7}, [pc] ; {loc:x} = {val:08x} {self.description(val)} float={flt:.7g}'
            elif h & 0xF000 == 0x5000:
                text = f'{["str","strh","strb","ldrsb","ldr","ldrh","ldrb","ldrsh"][(h >> 9) & 7]} r{a}, [r{b}, r{c}]'
            elif h & 0xE000 == 0x6000:
                text = f'{"ldr" if h & 2048 else "str"}{"b" if h & 4096 else ""} r{a}, [r{b}, #{((h >> 6) & 31) * (1 if h & 4096 else 4)}]'
            elif h & 0xF000 == 0x8000:
                text = f'{"ldrh" if h & 2048 else "strh"} r{a}, [r{b}, #{((h >> 6) & 31) * 2}]'
            elif h & 0xF000 == 0x9000:
                text = f'{"ldr" if h & 2048 else "str"} r{(h >> 8) & 7}, [sp, #{(h & 255) * 4}]'
            elif h & 0xF000 == 0xA000:
                text = f'add r{(h >> 8) & 7}, {"sp" if h & 2048 else "pc"}, #{(h & 255) * 4}'
            elif h & 0xFF00 == 0xB000:
                text = f'{"sub" if h & 128 else "add"} sp, #{(h & 127) * 4}'
            elif h & 0xF600 == 0xB400:
                regs = [f'r{i}' for i in range(8) if h & (1 << i)]
                if h & 256:
                    regs.append('pc' if h & 2048 else 'lr')
                text = f'{"pop" if h & 2048 else "push"} {{{", ".join(regs)}}}'
            elif h & 0xF000 == 0xC000:
                text = f'{"ldmia" if h & 2048 else "stmia"} r{(h >> 8) & 7}!, {{{", ".join(f"r{i}" for i in range(8) if h & (1 << i))}}}'
            elif h & 0xF000 == 0xD000:
                text = f'b{["eq","ne","cs","cc","mi","pl","vs","vc","hi","ls","ge","lt","gt","le","?","swi"][(h >> 8) & 15]} {addr + 4 + signed(h & 255, 8) * 2:x}'
            elif h & 0xF800 == 0xE000:
                text = f'b {addr + 4 + signed(h & 2047, 11) * 2:x}'
            elif h & 0xF800 == 0xF000:
                lo = struct.unpack('<H', self.bytes_at(addr + 2, 2))[0]
                dest = addr + 4 + (signed(h & 2047, 11) << 12) + ((lo & 2047) << 1)
                if not lo & 4096:
                    dest &= ~3
                text = f'bl {dest:x} {self.stubs.get(dest, self.description(dest))}'
                size = 4
            print(f'{addr:04x}: {text}')
            if h & 0xF800 == 0xE000:
                dest = addr + 4 + signed(h & 2047, 11) * 2
                if addr + 2 >= pool and pool <= dest < end:
                    addr, pool = dest, end
                    continue
            addr += size


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--address', type=lambda s: int(s, 0))
    parser.add_argument('--function')
    args = parser.parse_args()
    ref = Reference()
    if args.function:
        ref.disassemble(args.function)
    elif args.address is not None:
        print(hex(args.address), ref.description(args.address))
    else:
        print(json.dumps({'sections': ref.sections, 'symbols': ref.symbols}, indent=2))
