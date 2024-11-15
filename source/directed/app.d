module directed.app; 

import std.getopt, std.file, std.stdio, std.bigint, std.string, std.conv, std.range;

import directed.interpreter, directed.peg, directed.misc;

int main(string[] args) {
	string input;
	string ascii;
	string graphviz;
	string[] debugOptions;
	string[] debugTypes;
	bool ast;
	arraySep = ",";
	auto info = getopt(args,
		"i|input", "Set the input for the program as an integer.", &input,
		"a|ascii", "Set the input for the program as an ASCII string (the LSB is the first char, the second LSB is the second char, etc.)", &ascii,
		"g|graphviz", "Generate a graphviz file to the specified location instead of running the program", &graphviz,
		"d|debug", "Set debug options (available options: step, print)", &debugOptions,
		"debugtypes", "Set which node types to debug", &debugTypes,
		"ast", "Print the AST instead of running the program", &ast,
	);
	if(info.helpWanted || args.length == 1) {
		defaultGetoptPrinter("Usage: "~args[0]~" [options] <file>\nOptions:", info.options);
		return 0;
	}
	if(debugOptions.length > 0) {
		debugInfo.enabled = true;
		foreach(string opt; debugOptions) {
			switch(opt) {
				case "step":
					debugInfo.step = true;
					break;
				case "print":
					debugInfo.print = true;
					break;
				default:
					stderr.writeln("Unknown debug option '"~opt~"'.");
					return 1;
			}
		}
		debugInfo.types = debugTypes;
	}
	if(args.length != 2) {
		if(args.length < 2)
			stderr.writeln("No input file supplied");
		else
			stderr.writeln("Too many input files supplied.");
		return 1;
	}
	BigInt inputNum = 0;
	if(input != "")
		inputNum = BigInt(input);
	else if(ascii != "") {
		for(long i = ascii.length-1; i >= 0; i--) {
			inputNum *= 256;
			inputNum |= cast(int)ascii[i];
		}
	}
	try {
		string filename = args[1];
		string code = readText(filename);
		if(ast) {
			writeln(Directed(code));
			return 0;
		}
		try {
			if(graphviz) {
				string text = codeToGraphviz(filename, code);
				std.file.write(graphviz, text);
				return 0;
			} else {
				auto ret = interpret(filename, code, inputNum);
				return ret.toInt();
			}
		} catch(InterpreterException e) {
			string[] lines;
			if(e.pos.filename == filename)
				lines = code.splitLines();
			else
				lines = readText(e.pos.filename).splitLines();
			string line = lines[e.pos.line >= lines.length ? $-1 : e.pos.line];
			string pre = (e.pos.line+1).to!string~"| ";
			stderr.writeln(pre~line);
			for(size_t i = 0; i < cast(long)pre.length-2; i++)
				stderr.write(' ');
			stderr.write("| ");
			foreach(size_t i, char c; line) {
				if(i == e.pos.col)
					stderr.write('^');
				else if(c == '\t')
					stderr.write('\t');
				else
					stderr.write(' ');
			}
			stderr.writeln();
			stderr.writeln(e.msg);
		}
	} catch(FileException e) {
		stderr.writeln("Could not read file ", args[1], ": ", e.msg);
	}
	return 0;
}
