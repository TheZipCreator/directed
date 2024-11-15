module directed.peg;

public import pegged.grammar;

mixin(grammar(`
Directed:
	Program < Decl* endOfInput
	Decl < NodeTypeDecl / Import
	NodeTypeDecl < NodeIdentifier ('(' Vars ')' / ^eps) (Vars / ^eps) '{' (Stmts / ^eps) '}'
	Import < "import" doublequote ~(!doublequote .)* doublequote "as" NodeIdentifier

	Vars < VarIdentifier+
	Stmts < Stmt+

	Stmt < Node ('->' Node)*

	Node < NamedNode / VarNode / SimpleNode / BlockNode
	NamedNode < VarIdentifier ':=' SimpleNode
	VarNode < VarIdentifier
	SimpleNode < (Value / NodeIdentifier) ('(' Value* ')')?
	BlockNode < '{' Stmt* '}'
	
	Value < Number / Char
	
	Number <~ '-'? [0-9]+
	Char <- quote (Escape / .) quote
	Escape <~ '\\' ([abefnrtv\\] / quote)
	SafeChar <- [!-&*-Z\\^-z|~]
	NodeIdentifier <~ (![a-z] SafeChar) SafeChar*
	VarIdentifier <~ [a-z] SafeChar*
	
	LineComment <~ '#' (!endOfLine .)* endOfLine

	Spacing <- :(' ' / '\t' / '\r' / '\n' / '\r\n' / LineComment)*
`));
