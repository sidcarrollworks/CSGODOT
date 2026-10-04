import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.address.Address;
import java.nio.file.*;
import java.io.*;

public class AuditDecompile extends GhidraScript {
    public void run() throws Exception {
        String[] args=getScriptArgs();
        if (args.length < 2) {
            throw new IllegalArgumentException("Usage: AuditDecompile.java output-directory VA [VA ...]");
        }
        Path output=Paths.get(args[0]); Files.createDirectories(output);
        DecompInterface d = new DecompInterface(); d.openProgram(currentProgram);
        for(int i=1;i<args.length;i++) {
            Address a=toAddr(args[i]); Function f=getFunctionAt(a); if(f==null) f=getFunctionContaining(a);
            if(f==null) { println("NO FUNCTION "+a); continue; }
            PrintWriter p=new PrintWriter(Files.newBufferedWriter(output.resolve(f.getEntryPoint()+".txt")));
            p.println("Function "+f.getEntryPoint()+" "+f.getName()+" size="+f.getBody().getNumAddresses());
            p.println("Callers:");
            for(Reference r:getReferencesTo(f.getEntryPoint())) { Function c=getFunctionContaining(r.getFromAddress()); if(c!=null) p.println(c.getEntryPoint()+" "+c.getName()+" via "+r.getFromAddress()); }
            p.println("Calls:"); for(Function c:f.getCalledFunctions(monitor)) p.println(c.getEntryPoint()+" "+c.getName());
            DecompileResults result=d.decompileFunction(f,90,monitor);
            if(result.decompileCompleted()) p.println(result.getDecompiledFunction().getC()); else p.println(result.getErrorMessage());
            p.close(); println("AUDIT DECOMPILE "+f.getEntryPoint()+" "+f.getName());
        }
        d.dispose();
    }
}
