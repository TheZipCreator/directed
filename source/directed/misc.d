module directed.misc;

import std.conv, std.algorithm;

struct DebugInfo {
	string[] callStack = [];
	string[] types = [];
	bool enabled = false;
	bool step = false;
	bool print = false;

	bool hasType(string name) => types.length == 0 || types.canFind(name);
}
DebugInfo debugInfo;

struct FilePos {
	string filename;
	size_t line, col;
}

class InterpreterException : Exception {
	private bool complete;
	FilePos pos;

	this(string msg) {
		super(msg);
	}

	this(FilePos pos, string msg) {
		super(msg);
		addPos(pos);
	}

	private void addPos(FilePos pos) {
		msg = pos.filename~":"~(pos.line+1).to!string~":"~(pos.col+1).to!string~": "~msg;
		this.pos = pos;
	}
}
