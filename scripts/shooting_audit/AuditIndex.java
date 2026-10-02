// Local static shooting audit. Outputs stay in the ignored .godot directory.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;
import java.nio.file.*;
import java.io.*;
import java.util.*;

public class AuditIndex extends GhidraScript {
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 2) {
            throw new IllegalArgumentException("Usage: AuditIndex.java targets.tsv output-directory");
        }
        Path targets = Paths.get(args[0]), output = Paths.get(args[1]);
        Files.createDirectories(output);
        PrintWriter refs = new PrintWriter(Files.newBufferedWriter(output.resolve("string-refs.tsv")));
        for (String row : Files.readAllLines(targets)) {
            String[] parts = row.split("\t", 2);
            Address addr = toAddr(parts[0]);
            ReferenceIterator it = currentProgram.getReferenceManager().getReferencesTo(addr);
            while (it.hasNext()) {
                Reference ref = it.next();
                Function f = getFunctionContaining(ref.getFromAddress());
                refs.println(parts[1]+"\t"+addr+"\t"+ref.getFromAddress()+"\t"+(f==null?"DATA":f.getEntryPoint()+"\t"+f.getName()));
            }
        }
        refs.close();
        PrintWriter functions = new PrintWriter(Files.newBufferedWriter(output.resolve("functions.tsv")));
        int count = 0;
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            functions.println(f.getEntryPoint()+"\t"+f.getBody().getNumAddresses()+"\t"+f.getName()); count++;
        }
        functions.close();
        PrintWriter symbols = new PrintWriter(Files.newBufferedWriter(output.resolve("weapon-symbols.tsv")));
        SymbolIterator si = currentProgram.getSymbolTable().getAllSymbols(true);
        while (si.hasNext()) {
            Symbol s = si.next(); String name = s.getName(true);
            if (name.matches("(?i).*(WeaponCSBase|CSWeaponBase|WeaponFamas|WeaponGlock|WeaponRevolver|WeaponTaser|WeaponM4A1|WeaponUSP|Recoil|AimPunch).*")) symbols.println(s.getAddress()+"\t"+name);
        }
        symbols.close();
        println("AUDIT INDEX: "+currentProgram.getName()+" functions="+count+" -> "+output);
    }
}
