// Read-only query batches over an analyzed CS2 binary, written for the tick
// audit (reference/research/tick-audit-cs2-2026-10-05.md). Run it headless
// with -noanalysis -readOnly: nothing is saved to the project.
// Usage: -postScript TickQuery.java <commands.txt> <output-dir>
// One command a line; blank lines and lines starting with # are skipped.
//   info                       the binary the project holds: its path, image base, MD5 and SHA-256
//   strings <regex>            defined strings matching, with every function that uses them
//   symbols <regex>            symbols (with namespaces) matching, at most 400
//   decompile <VA>             pseudocode of the function at or containing VA, with callers and callees
//   disasm <VA>                the function's instructions, every memory operand also read as f32 and f64
//   xrefs <VA>                 references to VA, with the containing function
//   callers <VA> <depth>       who calls the function, depth levels up
//   callees <VA> <depth>       what the function calls, depth levels down
//   vtable <VA> <count>        count pointers read from VA, with the function each points at
//   vtables <ClassRegex> [n]   MSVC RTTI read by hand: every vtable of the classes (or structs)
//                              whose name matches the whole regex, up to n slots each (default
//                              64), ending where the next vtable's locator or a non-code slot is
//   rtti <regex>               vftable symbols, where the analysis labelled any (it often has not)
//   func <VA>                  size, body and signature of the function at or containing VA
// decompile, disasm, callers, callees and func make a function for the run
// where the analysis left none (never saved); vtable and vtables only say so.
// Each command writes NNN-<command>.txt in the output directory; index.txt lists them.
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.mem.*;
import java.nio.file.*;
import java.io.*;
import java.util.*;
import java.util.regex.*;

public class TickQuery extends GhidraScript {
    private DecompInterface decompiler;

    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 2) {
            throw new IllegalArgumentException("Usage: TickQuery.java commands.txt output-directory");
        }
        Path commands = Paths.get(args[0]);
        Path output = Paths.get(args[1]);
        Files.createDirectories(output);
        decompiler = new DecompInterface();
        DecompileOptions options = new DecompileOptions();
        decompiler.setOptions(options);
        decompiler.openProgram(currentProgram);
        PrintWriter index = new PrintWriter(Files.newBufferedWriter(output.resolve("index.txt")));
        int n = 0;
        for (String raw : Files.readAllLines(commands)) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            n++;
            String[] parts = line.split("\\s+", 2);
            String cmd = parts[0];
            String rest = parts.length > 1 ? parts[1] : "";
            String safe = line.replaceAll("[^A-Za-z0-9_.-]+", "_");
            if (safe.length() > 60) safe = safe.substring(0, 60);
            String name = String.format("%03d-%s.txt", n, safe);
            StringWriter text = new StringWriter();
            PrintWriter p = new PrintWriter(text);
            p.println("# " + line);
            try {
                switch (cmd) {
                    case "info": info(p); break;
                    case "strings": strings(p, rest); break;
                    case "symbols": symbols(p, rest); break;
                    case "decompile": decompile(p, rest); break;
                    case "disasm": disasm(p, rest); break;
                    case "xrefs": xrefs(p, rest); break;
                    case "callers": tree(p, rest, true); break;
                    case "callees": tree(p, rest, false); break;
                    case "vtable": vtable(p, rest); break;
                    case "rtti": rtti(p, rest); break;
                    case "func": func(p, rest); break;
                    case "vtables": vtables(p, rest); break;
                    default: p.println("UNKNOWN COMMAND " + cmd);
                }
            } catch (Exception e) {
                p.println("ERROR " + e);
            }
            p.flush();
            Files.writeString(output.resolve(name), text.toString());
            index.println(name + "\t" + line);
            println("TICKQUERY " + name);
        }
        index.close();
        decompiler.dispose();
    }

    // A slot the analysis left without a function gets one made for this run
    // (never saved: the project is opened read-only).
    private Function functionFor(String va) {
        Address a = toAddr(va.trim());
        Function f = getFunctionAt(a);
        if (f == null) f = getFunctionContaining(a);
        if (f == null) {
            try {
                if (getInstructionAt(a) == null) disassemble(a);
                f = createFunction(a, null);
            } catch (Exception e) {
                f = null;
            }
        }
        return f;
    }

    private String describe(Function f) {
        return f == null ? "NO FUNCTION" : f.getEntryPoint() + " " + f.getName(true) + " size=" + f.getBody().getNumAddresses();
    }

    // Which binary the addresses belong to: they hold only for this hash.
    private void info(PrintWriter p) {
        p.println("program " + currentProgram.getName());
        p.println("path " + currentProgram.getExecutablePath());
        p.println("format " + currentProgram.getExecutableFormat());
        p.println("image base " + currentProgram.getImageBase());
        p.println("md5 " + currentProgram.getExecutableMD5());
        p.println("sha256 " + currentProgram.getExecutableSHA256());
    }

    private void strings(PrintWriter p, String regex) {
        Pattern pattern = Pattern.compile(regex);
        int shown = 0;
        DataIterator it = currentProgram.getListing().getDefinedData(true);
        while (it.hasNext() && shown < 300) {
            Data d = it.next();
            if (!d.hasStringValue()) continue;
            Object value = d.getValue();
            if (value == null) continue;
            String s = value.toString();
            if (!pattern.matcher(s).find()) continue;
            shown++;
            p.println(d.getAddress() + "\t\"" + s.replace("\n", "\\n") + "\"");
            int refs = 0;
            for (Reference r : getReferencesTo(d.getAddress())) {
                Function f = getFunctionContaining(r.getFromAddress());
                p.println("    ref " + r.getFromAddress() + " in " + (f == null ? "DATA" : describe(f)));
                if (++refs >= 40) { p.println("    ..."); break; }
            }
        }
        if (shown >= 300) p.println("... (first 300 shown)");
    }

    private void symbols(PrintWriter p, String regex) {
        Pattern pattern = Pattern.compile(regex);
        int shown = 0;
        SymbolIterator it = currentProgram.getSymbolTable().getAllSymbols(false);
        while (it.hasNext() && shown < 400) {
            Symbol s = it.next();
            String name = s.getName(true);
            if (!pattern.matcher(name).find()) continue;
            shown++;
            Function f = getFunctionAt(s.getAddress());
            p.println(s.getAddress() + "\t" + s.getSymbolType() + "\t" + name + (f != null ? "\t[function size=" + f.getBody().getNumAddresses() + "]" : ""));
        }
        if (shown >= 400) p.println("... (first 400 shown)");
    }

    private void decompile(PrintWriter p, String va) {
        Function f = functionFor(va);
        if (f == null) { p.println("NO FUNCTION " + va); return; }
        p.println("Function " + describe(f));
        p.println("Callers:");
        for (Function c : f.getCallingFunctions(monitor)) p.println("  " + describe(c));
        p.println("Calls:");
        for (Function c : f.getCalledFunctions(monitor)) p.println("  " + describe(c));
        DecompileResults result = decompiler.decompileFunction(f, 180, monitor);
        if (result.decompileCompleted()) p.println(result.getDecompiledFunction().getC());
        else p.println("DECOMPILE FAILED: " + result.getErrorMessage());
    }

    private void disasm(PrintWriter p, String va) {
        Function f = functionFor(va);
        if (f == null) { p.println("NO FUNCTION " + va); return; }
        p.println("Function " + describe(f));
        InstructionIterator it = currentProgram.getListing().getInstructions(f.getBody(), true);
        int count = 0;
        while (it.hasNext() && count < 6000) {
            Instruction ins = it.next();
            StringBuilder b = new StringBuilder();
            b.append(ins.getAddress()).append("  ").append(ins.toString());
            for (Reference r : ins.getReferencesFrom()) {
                Address to = r.getToAddress();
                Data d = getDataAt(to);
                Function g = getFunctionAt(to);
                if (g != null) { b.append("   -> ").append(g.getName(true)); continue; }
                if (!to.isMemoryAddress()) continue;
                // Data the analysis defined (an undefined4, say) shows only its
                // default form, so every memory operand is read as floats too.
                b.append("   -> ").append(d != null ? "data " : "").append(to);
                if (d != null) b.append(" = ").append(d.getDefaultValueRepresentation());
                try {
                    b.append(" f32=").append(Float.intBitsToFloat(getInt(to)))
                     .append(" f64=").append(Double.longBitsToDouble(getLong(to)));
                } catch (Exception e) { }
            }
            p.println(b);
            count++;
        }
    }

    private void xrefs(PrintWriter p, String va) {
        Address a = toAddr(va.trim());
        int count = 0;
        for (Reference r : getReferencesTo(a)) {
            Function f = getFunctionContaining(r.getFromAddress());
            p.println(r.getFromAddress() + "\t" + r.getReferenceType() + "\t" + (f == null ? "DATA" : describe(f)));
            if (++count >= 400) { p.println("..."); break; }
        }
    }

    private void tree(PrintWriter p, String rest, boolean up) {
        String[] a = rest.trim().split("\\s+");
        Function f = functionFor(a[0]);
        int depth = a.length > 1 ? Integer.parseInt(a[1]) : 2;
        if (f == null) { p.println("NO FUNCTION " + a[0]); return; }
        Set<Function> seen = new HashSet<>();
        walk(p, f, 0, depth, up, seen);
    }

    private void walk(PrintWriter p, Function f, int level, int depth, boolean up, Set<Function> seen) {
        p.println("  ".repeat(level) + describe(f) + (seen.contains(f) ? " (again)" : ""));
        if (level >= depth || seen.contains(f) || seen.size() > 1500) return;
        seen.add(f);
        Set<Function> next = up ? f.getCallingFunctions(monitor) : f.getCalledFunctions(monitor);
        for (Function g : next) walk(p, g, level + 1, depth, up, seen);
    }

    private void vtable(PrintWriter p, String rest) throws Exception {
        String[] a = rest.trim().split("\\s+");
        Address at = toAddr(a[0]);
        int count = a.length > 1 ? Integer.parseInt(a[1]) : 64;
        for (int i = 0; i < count; i++) {
            Address slot = at.add(8L * i);
            long value = getLong(slot);
            Address to = toAddr(value);
            Function f = getFunctionAt(to);
            p.println(String.format("[%3d] %s -> %s %s", i, slot, to, f == null ? "(not a function)" : describe(f)));
        }
    }

    private void rtti(PrintWriter p, String regex) throws Exception {
        Pattern pattern = Pattern.compile(regex);
        SymbolIterator it = currentProgram.getSymbolTable().getAllSymbols(false);
        int shown = 0;
        while (it.hasNext() && shown < 20) {
            Symbol s = it.next();
            if (!s.getName().contains("vftable")) continue;
            String name = s.getName(true);
            if (!pattern.matcher(name).find()) continue;
            shown++;
            p.println("== " + s.getAddress() + " " + name);
            vtable(p, s.getAddress().toString() + " 64");
        }
        if (shown == 0) p.println("no vftable symbol matches");
    }

    // MSVC RTTI by hand: ".?AV<class>@@" sits 16 bytes into its TypeDescriptor;
    // a CompleteObjectLocator (signature 1) holds the descriptor's RVA at +12;
    // the 8 bytes before a vtable's first slot point at its locator.
    private byte[] imageBytes;
    private long imageBase;

    private void loadImage() throws Exception {
        if (imageBytes != null) return;
        Memory memory = currentProgram.getMemory();
        imageBase = currentProgram.getImageBase().getOffset();
        long end = imageBase;
        for (MemoryBlock b : memory.getBlocks()) {
            if (b.isInitialized() && b.getStart().isMemoryAddress()) end = Math.max(end, b.getEnd().getOffset() + 1);
        }
        imageBytes = new byte[(int) (end - imageBase)];
        for (MemoryBlock b : memory.getBlocks()) {
            if (!b.isInitialized() || !b.getStart().isMemoryAddress()) continue;
            long off = b.getStart().getOffset() - imageBase;
            if (off < 0) continue;
            byte[] chunk = new byte[(int) b.getSize()];
            b.getBytes(b.getStart(), chunk);
            System.arraycopy(chunk, 0, imageBytes, (int) off, chunk.length);
        }
    }

    // Whether va is a CompleteObjectLocator: signature 1 and its own RVA at
    // +20. The word after a vtable's last slot points at the next one's.
    private boolean isLocator(long va) {
        long off = va - imageBase;
        if (off < 0 || off + 24 > imageBytes.length) return false;
        return i32((int) off) == 1 && i32((int) off + 20) == (int) off;
    }

    private boolean isCode(Address to) {
        MemoryBlock b = currentProgram.getMemory().getBlock(to);
        return b != null && b.isExecute();
    }

    private int i32(int at) {
        return (imageBytes[at] & 0xff) | (imageBytes[at + 1] & 0xff) << 8 | (imageBytes[at + 2] & 0xff) << 16 | (imageBytes[at + 3] & 0xff) << 24;
    }

    private long i64(int at) {
        return (i32(at) & 0xffffffffL) | ((long) i32(at + 4)) << 32;
    }

    private void vtables(PrintWriter p, String rest) throws Exception {
        String[] a = rest.trim().split("\\s+");
        Pattern pattern = Pattern.compile(a[0]);
        int count = a.length > 1 ? Integer.parseInt(a[1]) : 64;
        loadImage();
        int shown = 0;
        DataIterator it = currentProgram.getListing().getDefinedData(true);
        while (it.hasNext() && shown < 12) {
            Data d = it.next();
            if (!d.hasStringValue() || d.getValue() == null) continue;
            String s = d.getValue().toString();
            if (!(s.startsWith(".?AV") || s.startsWith(".?AU")) || !s.endsWith("@@")) continue;
            String cls = s.substring(4, s.length() - 2);
            if (!pattern.matcher(cls).matches()) continue;
            shown++;
            long td = d.getAddress().getOffset() - 16;
            int tdRva = (int) (td - imageBase);
            p.println("== class " + cls + " TypeDescriptor " + Long.toHexString(td));
            for (int i = 0; i + 24 <= imageBytes.length; i += 4) {
                if (i32(i) != 1 || i32(i + 12) != tdRva) continue;
                int self = i32(i + 20);
                if (self != i) continue;
                int offset = i32(i + 4);
                long col = imageBase + i;
                for (int j = 0; j + 8 <= imageBytes.length; j += 8) {
                    if (i64(j) != col) continue;
                    long vt = imageBase + j + 8;
                    p.println("-- vtable " + Long.toHexString(vt) + " (this offset " + offset + ", locator " + Long.toHexString(col) + ")");
                    for (int k = 0; k < count; k++) {
                        int slot = j + 8 + 8 * k;
                        if (slot + 8 > imageBytes.length) break;
                        if (isLocator(i64(slot))) break;
                        Address to = toAddr(i64(slot));
                        Function f = getFunctionAt(to);
                        if (f == null && k > 0 && !isCode(to)) break;
                        p.println(String.format("  [%3d] %s", k, f == null ? to + " (not a function)" : describe(f)));
                    }
                }
            }
        }
        if (shown == 0) p.println("no class matches " + a[0]);
    }

    private void func(PrintWriter p, String va) {
        Function f = functionFor(va);
        if (f == null) { p.println("NO FUNCTION " + va); return; }
        p.println(describe(f));
        p.println("body " + f.getBody());
        p.println("signature " + f.getSignature().getPrototypeString());
    }
}
