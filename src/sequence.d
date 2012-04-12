import std.traits;
import std.stdio;
import std.exception;
import std.algorithm;
import std.array;
import std.conv;

struct SequencePattern {
	string prefix,suffix;
	ubyte padding;
	string toString() const {
		auto app = appender!string();
		app.reserve(prefix.length+suffix.length+padding);
		app.put(prefix);
		foreach(i;0..padding)
			app.put('#');
		app.put(suffix);
		return app.data();
	}
	const bool opEquals(ref const SequencePattern s) {
		return this.padding==s.padding && this.suffix==s.suffix && this.prefix==s.prefix;
	}
}

SequencePattern parse(string filename) {
	immutable auto patternAndSuffix  = find(filename,'#');
	immutable auto prefix = filename[0..$-patternAndSuffix.length];
	immutable auto suffix = find!"a!=b"(patternAndSuffix,'#');
	immutable auto padding = filename.length - prefix.length - suffix.length;
	enforce(padding<=ubyte.max);
	return SequencePattern(prefix,suffix,cast(ubyte)padding);
}

unittest {
	static assert( parse("") == SequencePattern("","",0) );
	static assert( parse("file.png") == SequencePattern("file.png","",0) );
	static assert( parse("file.###.png") == SequencePattern("file.",".png",3) );
	static assert( parse("###") == SequencePattern("","",3) );
}

char[] itoa(in uint value, in uint padding){
	char[] output = new char[padding];
	itoa(value,output);
	return output;
}

void itoa(uint value, out char[] range) in {enforce(range.length>=std.math.log10(value));} body {
	foreach(ref c ; range){
		c="0123456789"[value % 10];
		value/=10;
	}
	range.reverse;
}

unittest {
	assert( itoa(0,10) == "0000000000");
	assert( itoa(1234,5) == "01234");
}

string instanciate(in SequencePattern pattern, in uint frame){
	auto app = appender!string();
	app.reserve(pattern.prefix.length+pattern.suffix.length+pattern.padding);
	app.put(pattern.prefix);
	app.put(itoa(frame, pattern.padding));
	app.put(pattern.suffix);
	return app.data;
}

unittest {
	assert( instanciate(SequencePattern("file.",".ext",5),1234) == "file.01234.ext");
}

struct Range {
	uint first,last;
	string toString() const {
		return '['~to!string(first)~':'~to!string(last)~']';
	}
}

struct Sequence {
	SequencePattern pattern;
	Range range;
	uint step = 1;
	string toString() const {
		string noStep = pattern.toString~' '~range.toString;
		if(step>1)
			return noStep~':'~to!string(step);
		return noStep;
	}
}