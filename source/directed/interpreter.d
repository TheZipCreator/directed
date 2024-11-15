module directed.interpreter;

import std.bigint, std.stdio, std.conv, std.algorithm, std.array, std.typecons;

import directed.peg, directed.graph, directed.misc;


/// A graph being run
class GraphInstance {
	/// The graph
	Graph graph;
	/// All executors
	Executor[] execs;
	/// Executors that should be added
	Executor[] toAdd;
	/// Value to return
	Nullable!BigInt returnVal;
	/// Debug mode
	bool debugMode;
	/// Lists of lists of executors waiting at junctions
	Executor[][][ulong] junctions;
	
	/// A class that executes nodes
	final class Executor {
		/// Top ID reached
		static ulong topID = 0;
		/// The ID of this executor
		ulong id;

		/// What node the Executor is currently at
		Node node;
		/// Edge index that was just followed
		size_t edgeIndex = 0;
		/// The accumulator
		BigInt accumulator; 
		/// Current junction spot waiting in (if any)
		Nullable!(Executor[]) waiting;
		/// Whether this executor should be removed
		bool remove = false;

		this(Node node, BigInt accumulator = BigInt(0), bool move = false) {
			id = topID++;
			this.node = node;
			this.accumulator = accumulator;
			if(move)
				moveTo(node);
		}

		this(Node node) {
			id = topID++;
			this.node = node;
			accumulator = BigInt(0);
			moveTo(node);
		}

		private void processReturnVal(ReturnVal ret) {
			final switch(ret.type) {
				case ReturnType.VALUE:
					accumulator = ret.value;
					break;
				case ReturnType.RETURN:
					returnVal = ret.value;
					break;
				case ReturnType.DIE:
					remove = true;
					break;
				case ReturnType.DIE_ALL:
					foreach(exec; execs)
						exec.remove = true;
					break;
			}
		}
		
		/// Resolves nodes sitting at junctions
		void resolveJunction() {
			Executor[] spot;
			if(waiting.isNull) {
				// newly waiting, find a spot
				if(node.id !in junctions) {
					// If no nodes waiting yet, register a new spot
					junctions[node.id] = [new Executor[node.parents.length]];
					spot = junctions[node.id][$-1];
				} else {
					// look for open spots
					auto toCheck = junctions[node.id];
					bool found = false;
					foreach(j; toCheck) {
						if(j[edgeIndex] is null) {
							j[edgeIndex] = this;
							spot = j;
							found = true;
							break;
						}
					}
					if(!found) {
						// create new spot
						junctions[node.id] ~= [new Executor[node.parents.length]];
						spot = junctions[node.id][$-1];
					}
				}
				spot[edgeIndex] = this;
				waiting = spot;
			} else {
				spot = waiting.get;
			}
			// check if spot is full
			if(!spot.all!(x => x !is null))
				return; // not enough
			// enough
			waiting = Nullable!(Executor[]).init;
			processReturnVal(node.type.execute(spot.map!(x => x.accumulator).array));
			foreach(exec; spot)
				if(exec != this)
					exec.remove = true;
			junctions[node.id] = junctions[node.id].remove!(x => x == spot);
		}
		
		/// Moves to another node
		void moveTo(Node other) {
			Node prev = node;
			node = other;
			if(cast(Junction)other.type && other.parents.length > 1) {
				edgeIndex = other.parents.countUntil(prev);
				resolveJunction();
				return;
			}
			processReturnVal(node.type.execute([accumulator]));
		}
		
		/// Steps to the next node
		void step() {
			if(remove)
				return; // don't do anything if we're not supposed to exist
			if(!waiting.isNull) {
				resolveJunction();
				return;
			}
			if(node.children.length == 0) {
				remove = true;
				return;
			}
			foreach(i, child; node.children[1..$]) {
				auto exec = new Executor(node, BigInt(accumulator));
				exec.moveTo(child);
				toAdd ~= exec;
			}
			moveTo(node.children[0]);
		}
		
		override string toString() const => "executor "~id.to!string~" @ "~node.toString()~" : "~accumulator.to!string;
	}

	this(Graph graph, BigInt[] args) {
		this.graph = graph;
		for(size_t i = 0; i < graph.inputNodes.length; i++) {
			execs ~= new Executor(graph.inputNodes[i], args[i]);
		}
		foreach(node; graph.parentlessNodes) {
			execs ~= new Executor(node);
		}
	}

	void step() {
		foreach(exec; execs) {
			exec.step();
			if(debugInfo.print && debugInfo.hasType(graph.name))
				stderr.writeln(exec);
			if(!returnVal.isNull)
				return;
		}
		execs = execs.filter!(x => !x.remove).array;
		foreach(exec; toAdd) {
			if(debugInfo.print && debugInfo.hasType(graph.name))
				stderr.writeln(exec);
			execs ~= exec;
		}
		toAdd = [];
		if(debugInfo.enabled && debugInfo.hasType(graph.name)) {
			if(debugInfo.print)
				stderr.writeln("---");
			if(debugInfo.step) {
				write("[Enter]");
				readln();
			}
		}
		stdout.flush();
	}
	
	ReturnVal execute() {
		if(debugInfo.enabled && debugInfo.hasType(graph.name)) {
			debugInfo.callStack ~= graph.name;
			if(debugInfo.print) {
				stderr.writeln("=== ", graph.name, " ===");
				foreach(exec; execs) {
					if(debugInfo.print)
						stderr.writeln(exec);
				}
				stderr.writeln("---");
			}
		}
		scope(exit) {
			if(debugInfo.enabled && debugInfo.hasType(graph.name)) {
				debugInfo.callStack = debugInfo.callStack[0..$-1];
				if(debugInfo.print && debugInfo.callStack.length > 0)
					stderr.writeln("=== ", debugInfo.callStack[$-1], " ===");
			}
		}
		while(execs.length > 0) {
			step();
			if(!returnVal.isNull)
				return ReturnVal(ReturnType.VALUE, returnVal.get);
		}
		return ReturnVal(ReturnType.DIE);
	}
}

class Interpreter {
	string[] importStack = []; /// Stack of previous imports
	string filename, code;
	NodeType[string] types;
	this(string filename, string code) {
		this.filename = filename;
		this.code = code;
		types = cast(NodeType[string])[
			"Out": OutNodeType.instance,
			"+": OperatorNodeType!"+".instance,
			"-": OperatorNodeType!"-".instance,
			"*": OperatorNodeType!"*".instance,
			"/": OperatorNodeType!"/".instance,
			"%": OperatorNodeType!"%".instance,
			"&": OperatorNodeType!"&".instance,
			"|": OperatorNodeType!"|".instance,
			"^": OperatorNodeType!"^".instance,
			"=": ConditionalNodeType!("==", "=").instance,
			"!=": ConditionalNodeType!("!=").instance,
			">": ConditionalNodeType!(">").instance,
			">=": ConditionalNodeType!(">=").instance,
			"<": ConditionalNodeType!("<").instance,
			"<=": ConditionalNodeType!("<=").instance,
			"Nop": NopNodeType.instance,
			"Return": ReturnNodeType.instance,
			"Die": DieNodeType.instance,
			"Use": UseNodeType.instance
		];
	}

	private FilePos filepos(ParseTree pt) => filepos(pt.begin);

	private FilePos filepos(size_t pos) {
		size_t line = 0;
		size_t col = 0;
		for(size_t i = 0; i < pos; i++) {
			if(code[i] == '\r')
				continue;
			col++;
			if(code[i] == '\n') {
				line++;
				col = 0;
			}
		}
		return FilePos(filename, line, col);
	}

	private BigInt value(ParseTree value) {
		auto lit = value[0];
		final switch(lit.name) {
			case "Directed.Number":
				return BigInt(lit.matches[0]);
			case "Directed.Char":
				if(lit.children.length > 0) {
					final switch(lit[0].matches[0][1]) {
						case 'a': return BigInt(cast(int)'\a');
						case 'b': return BigInt(cast(int)'\b');
						case 'e': return BigInt(cast(int)'\033');
						case 'f': return BigInt(cast(int)'\f');
						case 'n': return BigInt(cast(int)'\n');
						case 'r': return BigInt(cast(int)'\r');
						case 't': return BigInt(cast(int)'\t');
						case 'v': return BigInt(cast(int)'\v');
						case '\\': return BigInt(cast(int)'\\');
						case '\'': return BigInt(cast(int)'\'');
					}
				}
				return BigInt(cast(int)lit.matches[1][0]);
		}
	}

	void getDecls() {
		ParseTree tree = Directed(code);
		if(!tree.successful)
			throw new InterpreterException(filepos(tree.failEnd), "Invalid syntax.");
		tree = tree[0];
		foreach(declParent; tree) {
			auto decl = declParent[0];
			final switch(decl.name) {
				case "Directed.NodeTypeDecl": {
					string declName = decl[0].matches[0];
					if(declName in types) {
						throw new InterpreterException(filepos(decl), "Node type '"~declName~"' redeclared.");
					}
					Node[] nodes;
					Node[string] names;
					Node[] parse(ParseTree[] arr) {
						Node[] ret;
						Node[] parseNode(ParseTree n) {
							final switch(n.name) {
								case "Directed.NamedNode": {
									string name = n[0].matches[0];
									if(name in names)
										throw new InterpreterException(filepos(n), "Node name '"~name~"' can not be reused.");
									auto node = parseNode(n[1])[0];
									node.name = name;
									names[name] = node;
									return [node];
								}
								case "Directed.VarNode": {
									string name = n[0].matches[0];
									if(name !in names)
										throw new InterpreterException(filepos(n), "Node '"~name~"' does not exist.");
									return [names[name]];
								}
								case "Directed.SimpleNode": {
									auto lit = n[0];
									Node node;
									final switch(lit.name) {
										case "Directed.Value": node = new Node(LiteralNodeType.of(value(lit)), filepos(n)); break;
										case "Directed.NodeIdentifier": {
											string ident = lit.matches[0];
											if(ident !in types)
												throw new InterpreterException(filepos(lit), "Unknown node type '"~ident~"'.");
											auto type = types[ident];
											if(n.children.length > 1) {
												if(auto p = cast(Parameterizable)type) {
													auto params = n.children[1..$].map!(x => value(x)).array;
													auto range = p.parameterRange;
													if(!range.includes(params.length)) {
														if(range.min != range.max)
															throw new InterpreterException(
																filepos(n), 
																"Node expects between "~range.min.to!string~" and "~range.max.to!string~" parameters."
															);
														else
															throw new InterpreterException(filepos(n), "Node expects exactly "~range.min.to!string~
																" parameter"~(range.min == 1 ? "" : "s")~".");
													}
													type = p.parameterize(params);
												} else
													throw new InterpreterException(filepos(n), "Node can not be parameterized.");
											}
											node = new Node(type, filepos(n));
											break;
										}
									}
									nodes ~= node;
									return [node];
								}
								case "Directed.BlockNode":
									return parse(n.children);
							}
						}
						foreach(stmt; arr) {
							auto first = parseNode(stmt[0][0]);
							auto currs = first;
							foreach(child; stmt[1..$]) {
								auto next = parseNode(child[0]);
								foreach(c; currs) {
									foreach(n; next) {
										c.children ~= n;
										n.parents ~= c;
									}
								}
								currs = next;
							}
							ret ~= first;
						}
						return ret;
					}
					size_t nparameters = decl[1].children.length;
					string[] inputNodeNames;
					Node[] inputNodes;
					foreach(inp; decl[1].children~decl[2].children) {
						auto node = new Node(NopNodeType.instance, filepos(inp), inp.matches[0]);
						nodes ~= node;
						inputNodes ~= node;
						inputNodeNames ~= inp.matches[0];
						names[node.name] = node;
					}
					parse(decl[3].children);
					auto graph = new Graph(nodes, declName, nparameters, inputNodeNames, inputNodes);
					if(graph.nargs > 1)
						types[declName] = new JunctionGraphNodeType(graph);
					else
						types[declName] = new GraphNodeType(graph);
					break;
				}
				case "Directed.Import": {
					import std.path, std.file;
					try {
						string ifilename = buildPath(filename.dirName, decl.matches[2]);
						if(importStack.canFind(ifilename))
							throw new InterpreterException(filepos(decl), "Cyclic imports are not allowed.");
						string namespace = decl.matches[5];
						string icode = readText(ifilename);
						auto interpreter = new Interpreter(ifilename, icode);
						interpreter.importStack = importStack~filename;
						interpreter.getDecls();
						foreach(type; interpreter.types.values) {
							if(auto g = cast(GraphNodeType)type) {
								string name = g.graph.name == "Main" ? namespace : namespace~"."~g.graph.name;
								types[name] = type;
							}
						}
						break;
					} catch(FileException e) {
						throw new InterpreterException(filepos(decl), "Can't open file: "~e.msg);
					}
					
				}
			}
		}

	}

	/// Interprets a parse tree
	BigInt interpret(BigInt input) {
		getDecls();
		if("Main" !in types)
			throw new InterpreterException(FilePos(filename, 0, 0), "There must be a node type named 'Main'.");
		auto main = cast(GraphNodeType)types["Main"];
		auto graph = main.graph;
		if(graph.nparameters > 0)
			throw new InterpreterException(graph.inputNodes[0].pos, "Main must not take any parameters.");
		if(graph.nargs > 1)
			throw new InterpreterException(graph.inputNodes[1].pos, "Main can only take 0 or 1 arguments.");
		auto ret = new GraphInstance(graph, graph.nargs == 0 ? [] : [input]).execute(); 
		if(ret.type == ReturnType.RETURN)
			return ret.value;
		return BigInt(0);
	}
}
/// Interprets a string
BigInt interpret(string filename, string code, BigInt input) => 
	new Interpreter(filename, code).interpret(input);
/// Creates a graphviz file from the given code
string codeToGraphviz(string filename, string code) {
	auto interpreter = new Interpreter(filename, code);
	interpreter.getDecls();

	auto ap = appender!string;
	ap ~= "digraph G {";
	ap ~= `fontname="Liberation Mono";`;
	ap ~= `node[fontname="Liberation Mono"];`;
	ap ~= `edge[fontname="Liberation Mono"];`;
	foreach(type; interpreter.types.values) {
		if(auto g = cast(GraphNodeType)type) {
			ap ~= g.graph.graphviz();
		}
	}
	ap ~= "}";
	return ap.data;
}
