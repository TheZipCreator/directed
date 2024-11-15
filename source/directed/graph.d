module directed.graph;

import std.bigint, std.stdio, std.conv, std.algorithm, std.array, std.typecons;

import directed.misc, directed.interpreter;

/// Range of arguments
struct ArgRange {
	static enum ANY = ArgRange(0, size_t.max);

	size_t min, max;

	bool includes(size_t x) => x >= min && x <= max;
}

/// What to do on return
enum ReturnType : ubyte {
	/// Just a normal value
	VALUE,
	/// Return this value
	RETURN,
	/// No value was returned
	DIE,
	/// Kill everything
	DIE_ALL
}

struct ReturnVal {
	ReturnType type;
	BigInt value;
}

/// Type of a node
interface NodeType {
	/// Executes the node on the given arguments
	ReturnVal execute(BigInt[] args);
	/// Returns a string representation of the node type
	string toString() const;
}

/// Parameterizable node type
interface Parameterizable {
	/// Range for possible parameters. If the min is > 0, then the node is not allowed to be used directly
	ArgRange parameterRange();
	NodeType parameterize(BigInt[] parameters);
}

/// Junction type
interface Junction {
	/// Range of amount of inputs
	ArgRange range();
}

/// No operation
class NopNodeType : NodeType {
	static typeof(this) instance;

	static this() { instance = new typeof(this)(); }
	private this() {}
	ReturnVal execute(BigInt[] args) => ReturnVal(ReturnType.VALUE, args[0]);
	override string toString() const => "Nop";
}
/// Dies
class DieNodeType : NodeType {
	static typeof(this) instance;

	static this() { instance = new typeof(this)(); }
	private this() {}
	ReturnVal execute(BigInt[] _) => ReturnVal(ReturnType.DIE_ALL);
	override string toString() const => "Die";
}
/// Returns a value
class ReturnNodeType : NodeType {
	static typeof(this) instance;

	static this() { instance = new typeof(this)(); }
	private this() {}
	ReturnVal execute(BigInt[] args) => ReturnVal(ReturnType.RETURN, args[0]);
	override string toString() const => "Return";
}
/// Unparameterized Use
class UseNodeType : NodeType, Parameterizable {
	static typeof(this) instance;

	static this() { instance = new typeof(this)(); }
	private this() {}
	ReturnVal execute(BigInt[] _) => assert(false);
	override string toString() const => "Use";

	ArgRange parameterRange() => ArgRange(1, 1);
	NodeType parameterize(BigInt[] params) => new ParameterizedUseNodeType(params[0]);
}
class ParameterizedUseNodeType : NodeType, Junction {
	size_t index;

	ArgRange range() => ArgRange(index+1, size_t.max);

	ReturnVal execute(BigInt[] args) => ReturnVal(ReturnType.VALUE, args[index]);
	override string toString() const => "Use("~index.to!string~")";

	this(BigInt index) {
		this.index = index.toLong();
	}
}

/// A literal
class LiteralNodeType : NodeType {
	static LiteralNodeType[BigInt] literalCache;

	BigInt value;

	bool junction() => false;
	ReturnVal execute(BigInt[] _) => ReturnVal(ReturnType.VALUE, value);

	static LiteralNodeType of(BigInt value) {
		if(value !in literalCache)
			literalCache[value] = new LiteralNodeType(value);
		return literalCache[value];
	}

	private this(BigInt value) {
		this.value = value;
	}
	
	override string toString() const => value.to!string;
}

/// An output node
class OutNodeType : NodeType {
	static OutNodeType instance;


	ReturnVal execute(BigInt[] args) {
		write(cast(char)(args[0].toInt()));
		return ReturnVal(ReturnType.VALUE, args[0]);
	}
	
	static this() { instance = new OutNodeType(); }
	private this() {}
	
	override string toString() const => "Out";
}
/// An operator
class OperatorNodeType(string op, string name = op) : NodeType, Junction, Parameterizable {
	static typeof(this) instance;

	ReturnVal execute(BigInt[] args) {
		mixin(`auto val = reduce!((a, b) => a`~op~`b)(args[0], args[1..$]);`);
		return ReturnVal(ReturnType.VALUE, val);
	}

	ArgRange range() => ArgRange(1, size_t.max);

	ArgRange parameterRange() => ArgRange(0, size_t.max);
	NodeType parameterize(BigInt[] params) => new ParameterizedOperatorNodeType!(op, name)(params);

	static this() { instance = new typeof(this)(); }
	private this() {}

	override string toString() const => name;
}
class ParameterizedOperatorNodeType(string op, string name = op) : NodeType, Junction {
	BigInt[] params;

	this(BigInt[] params) {
		this.params = params;
	}
	
	ReturnVal execute(BigInt[] args) {
		auto combined = args~params;
		mixin(`auto val = reduce!((a, b) => a`~op~`b)(combined[0], combined[1..$]);`);
		return ReturnVal(ReturnType.VALUE, val);
	}
	
	ArgRange range() => ArgRange(1, size_t.max);
	
	override string toString() const => name~"("~params.map!(x => x.to!string).join(" ")~")";
}

private ReturnVal checkCond(string op)(BigInt[] args) {
	BigInt curr = args[0];
	foreach(arg; args[1..$]) {
		mixin(`if(!(curr `~op~` arg)) return ReturnVal(ReturnType.DIE);`);
	}
	return ReturnVal(ReturnType.VALUE, args[0]);
}

/// Conditional operator
class ConditionalNodeType(string op, string name = op) : NodeType, Junction, Parameterizable {
	static typeof(this) instance;

	ReturnVal execute(BigInt[] args) {
		return checkCond!op(args);
	}

	ArgRange range() => ArgRange(1, size_t.max);

	ArgRange parameterRange() => ArgRange(0, size_t.max);
	NodeType parameterize(BigInt[] params) => new ParameterizedConditionalNodeType!(op, name)(params);

	static this() { instance = new typeof(this)(); }
	private this() {}

	override string toString() const => name;
}
class ParameterizedConditionalNodeType(string op, string name = op) : NodeType, Junction {
	BigInt[] params;

	this(BigInt[] params) {
		this.params = params;
	}
	
	ReturnVal execute(BigInt[] args) {
		return checkCond!op(args~params);
	}
	
	ArgRange range() => ArgRange(1, size_t.max);
	
	override string toString() const => name~"("~params.map!(x => x.to!string).join(" ")~")";
}

/// Node with a subgraph in it
class GraphNodeType : NodeType, Parameterizable {
	/// The graph to execute
	Graph graph;

	this(Graph graph) {
		this.graph = graph;
	}

	ReturnVal execute(BigInt[] args) {
		auto instance = new GraphInstance(graph, args);	
		return instance.execute();
	}

	ArgRange parameterRange() => ArgRange(graph.nparameters, graph.nparameters);
	NodeType parameterize(BigInt[] params) => new ParameterizedGraphNodeType(graph, params);
	
	override string toString() const => graph.name;
}
/// Parameterized graph node
class ParameterizedGraphNodeType : NodeType {
	/// The graph to execute
	Graph graph;
	/// Parameters
	BigInt[] parameters;

	this(Graph graph, BigInt[] parameters) {
		this.graph = graph;
		this.parameters = parameters;
	}

	override ReturnVal execute(BigInt[] args) {
		auto instance = new GraphInstance(graph, parameters~args);	
		return instance.execute();
	}
	
	override string toString() const => graph.name~"("~parameters.map!(x => x.to!string).join(" ")~")";
}

/// Node with a subgraph in it that's a junction
class JunctionGraphNodeType : GraphNodeType, Junction {
	ArgRange range() => ArgRange(graph.nargs, graph.nargs);
	
	this(Graph graph) {
		super(graph);
	}
	
	override NodeType parameterize(BigInt[] params) => new ParameterizedJunctionGraphNodeType(graph, params);
}

/// Node with a subgraph in it that's a junction and has parameters.
///
/// This has to be the longest class name I've ever created.
class ParameterizedJunctionGraphNodeType : ParameterizedGraphNodeType, Junction {
	ArgRange range() => ArgRange(graph.nargs, graph.nargs);
	
	this(Graph graph, BigInt[] parameters) {
		super(graph, parameters);
	}	
}

/// A node in a graph
class Node {
	static ulong topID = 0; /// Highest ID given so far

	/// Type of the node
	NodeType type;
	/// Nodes before this node
	Node[] parents;
	/// Nodes after this node
	Node[] children;
	/// Name of the node
	string name;
	/// File position of the node
	FilePos pos;
	/// ID
	ulong id;

	this(NodeType type, FilePos pos, string name = "") {
		this.type = type;
		this.pos = pos;
		this.name = name;
		id = topID++;
	}

	override string toString() const => type.toString()~(name == "" ? "" : "["~name~"]");
}

/// A graph
class Graph {
	/// List of all nodes
	Node[] nodes;
	/// List of all nodes without a parent, excluding input nodes
	Node[] parentlessNodes;
	/// Array of all input node names
	string[] inputNodeNames;
	/// Array of all input nodes
	Node[] inputNodes;
	/// Number of parameters
	size_t nparameters;
	/// Number of arguments
	size_t nargs;
	/// Name of the graph
	string name;
	
	this(Node[] nodes, string name, size_t nparameters, string[] inputNodeNames, Node[] inputNodes) {
		this.nodes = nodes;
		this.name = name;
		this.nparameters = nparameters;
		nargs = inputNodes.length-nparameters;
		this.inputNodeNames = inputNodeNames;
		this.inputNodes = inputNodes;
		parentlessNodes = nodes.filter!(x => x.parents.length == 0 && !inputNodes.canFind(x)).array;
		// check nodes for errors
		foreach(node; nodes) {
			if(auto j = cast(Junction)node.type) {
				if(!j.range.includes(node.parents.length))
					throw new InterpreterException(node.pos, "Incorrect number of arguments for junction.");
			}
			if(auto p = cast(Parameterizable)node.type) {
				if(!p.parameterRange.includes(0))
					throw new InterpreterException(node.pos, "Node must be parameterized.");
			}
		}
	}

	/// Converts to graphviz format
	///
	/// Note: produces a subgraph definition; you must wrap this in a larger graph.
	string graphviz() {
		auto ap = appender!string;
		ap ~= "subgraph \"cluster_"~name~"\"{";
		ap ~= "label=\""~name~"\"; color=blue;";
		foreach(size_t i, Node node; nodes) {
			bool input = inputNodes.canFind(node);
			ap ~= "id"~node.id.to!string~"[label=\""~(input ? node.name : node.type.toString())~"\""~(input ? " color=green" : "")~"];";
			foreach(child; node.children) {
				ap ~= "id"~node.id.to!string~"->id"~child.id.to!string;
				if(child.parents.length > 1 && cast(Junction)child.type)
					ap ~= "[label="~child.parents.countUntil(node).to!string~"]";
				ap ~= ";";
			}
		}
		ap ~= "}";
		return ap.data;
	}
}
