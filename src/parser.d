import sequence;

import std.exception  : enforce;
import std.functional : not;
import std.algorithm  : find, sort, uniq, max, minPos, map, countUntil, remove;
import std.ascii      : isDigit;
import std.array;
import std.conv       : to;
import std.file       : DirEntry, dirEntries, SpanMode;
import std.path       : baseName, dirName;
import std.stdio      : writeln;

struct BrowseItem {
	enum Type { FILE,FOLDER,SEQUENCE}
	Type type;
	string path;
	Sequence sequence;
	static BrowseItem create_file(string filename){
		return BrowseItem(Type.FILE, filename);
	}
	static BrowseItem create_folder(string filename){
		return BrowseItem(Type.FOLDER, filename);
	}
	static BrowseItem create_sequence(string path, Sequence sequence){
		return BrowseItem(Type.SEQUENCE, path, sequence);
	}
	const bool opEquals(ref const BrowseItem s) {
		return type==s.type&&path==s.path&&sequence==s.sequence;
	}
}

private:

struct Location {
	uint first,count;
	@property uint last() const {
		return first+count;
	}
}

uint atoi(const(char[]) number) {
	uint result;
	foreach(c;number){
		result*=10;
		result+=c-'0';
	}
	return result;
}

unittest {
	static assert(atoi("123")==123);
	static assert(atoi("001")==1);
}

struct PatternExtractor {
	void reset(string filename) {
		locations.clear();
		values.clear();
		key = filename.dup;
		auto range = key;
		while(!(range = find!isDigit(range)).empty){
			const posInFilename = cast(uint)(filename.length-range.length);
			auto afterDigit = find!(not!isDigit)(range);
			auto digits = range[0..$-afterDigit.length];
			locations~=Location(posInFilename,cast(uint)digits.length);
			values~=atoi(digits);
			digits[]='#';
			range = afterDigit;
		}
	}
	char[] key;
	Location[] locations;
	uint[] values;
}

unittest {
	PatternExtractor tmp;
	tmp.reset("toto.123.jp2k");
	assert(tmp.key=="toto.###.jp#k");
	assert(tmp.values==[123,2]);
	assert(tmp.locations==[Location(5,3),Location(11,1)]);
	tmp.reset("toto");
	assert(tmp.key=="toto");
	assert(tmp.values==[]);
	assert(tmp.locations==[]);
}

struct LocationData {
	bool canDismiss(ref uint value){
		if(values.empty)
			return false;
		sorted = values.dup;
		sort(sorted);
		distinctValues = std.range.walkLength(uniq(sorted));
		value=sorted[0];
		return distinctValues==1;
	}
	Location location;
	uint[] values;
	uint[] sorted;
	ulong distinctValues;
}

Range[] getRangeAndStep(const(uint[]) values, ref uint step){
	step=1;
	if(values.empty)
		return null;
	Range[] ranges;
	if(values.length==1){
		ranges~=Range(values[0], values[0]);
	}else{
		uint[] derivative;
		derivative~=0;
		uint min_derivative=uint.max;
		foreach(a,b;std.range.lockstep(values[0..$-1], values[1..$])) {
			uint diff = b-a;
			derivative~=diff;
			if(diff<min_derivative)
				min_derivative = diff;
		}
		step = max(1,min_derivative);
		foreach(current,diff;std.range.lockstep(values,derivative)) {
			if(!ranges.empty&&diff==step)
				ranges[$-1].last = current;
			else
				ranges~=Range(current,current);
		}
	}
	return ranges;
}

unittest{
	void check(uint[] values, Range[] expectedRanges, uint expectedStep){
		uint step;
		auto ranges = getRangeAndStep(values, step);
		assert(ranges == expectedRanges);
		assert(step == expectedStep);
	}
	check([], null, 1);
	check([1], [Range(1,1)], 1);
	check([1,3,5], [Range(1,5)], 2);
	check([1,2,3,5], [Range(1,3),Range(5,5)], 1);
}

class Pattern {
	this(char[] key, Location[] locations){
		this.key = key;
		foreach(location; locations)
			data ~= LocationData(location);
	}
	
	void prepare(){
		if(values.empty)
			return;
		//dipatching values
		if(values.length==1)
			data[0].values = values;
		else foreach(i, value; values)
			data[i%data.length].values~=value;
		// removing empty locations
		LocationData[] newData;
		uint valueToReplace;
		foreach(datum;data){
			if(datum.canDismiss(valueToReplace))
				overwrite(key, datum.location, valueToReplace);
			else
				newData~=datum;
		}
		data = newData;
		values = null; // cleaning
	}
	
	string toString() const {
		return to!string(key);
	}
	
	@property bool ready() const {
		return data.length==1;
	}
	
	Range[] getConsecutiveRanges(ref uint step) const {
		enforce(ready);
		return getRangeAndStep(data[0].sorted, step);
	}

	char[] key;
	uint[] values;
	LocationData[] data;
}

void overwrite(char[] key, in Location location, uint value){
	key[location.first..location.last] = itoa(value, location.count);
}

Pattern[] subdivide(Pattern pattern) {
	pattern.prepare();
	Pattern[] results;
	if(pattern.ready)
		results ~= pattern;
	else{
		auto pivot = minPos!"a.distinctValues<b.distinctValues"(pattern.data).front;
		auto otherColumns = remove(pattern.data.dup, countUntil(pattern.data, pivot));
		auto otherLocationData = array(map!"a.location"(otherColumns));
		Pattern[uint] patterns;
		foreach(value;pivot.sorted) {
			char[] newKey = pattern.key.dup;
			overwrite(newKey, pivot.location, value);
			patterns[value] = new Pattern(newKey, otherLocationData);
		}
		foreach(i;0..pivot.values.length){
			uint val(LocationData data){return data.values[i];}
			patterns[pivot.values[i]].values ~= array(map!(val)(otherColumns));
		}
		foreach(atom; patterns.values)
			results ~= subdivide(atom);
	}
	return results;
}

BrowseItem[] convert(in string path, in Pattern pattern){
	enforce(pattern.ready);
	BrowseItem[] results;
	uint step;
	auto sequencePattern = parse(to!string(pattern.key));
	foreach(range;pattern.getConsecutiveRanges(step))
		results~= BrowseItem.create_sequence(path, Sequence(sequencePattern, range, step));
	return results;
}

public struct Parser {
	alias Pattern[FolderPatternKey] PatternMap;
	PatternMap patternMap;
	BrowseItem[] items;
	
	void insert(string filename) {
		extractor.reset(baseName(filename));
		ingest(dirName(filename));
	}
	
	void insert(DirEntry entry) {
		auto name = entry.name;
		if(entry.isDir){
			items~=BrowseItem.create_folder(name);
			return;
		}
		extractor.reset(baseName(name));
		if(extractor.locations.empty){
			items~=BrowseItem.create_file(name);
			return;
		}
		ingest(dirName(name));
	}
	
	BrowseItem[] terminate(){
		foreach(key, pattern; patternMap)
			foreach(ready; subdivide(pattern))
				items~=convert(key.folder, ready);
		return items;
	}
private:
	void ingest(string dirName){
		auto mapKey = FolderPatternKey(dirName, to!string(extractor.key));
		auto pattern = mapKey in patternMap ? patternMap[mapKey] : (patternMap[mapKey] = new Pattern(extractor.key, extractor.locations));
		pattern.values~=extractor.values;
	}
	
	PatternExtractor extractor;
	struct FolderPatternKey {
		string folder;
		string key;
		string id;
		this(string folder, string key){
			this.folder = folder;
			this.key = key;
			id = key~folder;
		}
		const hash_t toHash() {
			return std.algorithm.reduce!"a*9+b"(id);
		}
		const bool opEquals(ref const FolderPatternKey s) {
			return this.id==s.id;
		}
		const int opCmp(ref const FolderPatternKey s) {
			return std.algorithm.cmp(this.id, s.id);
		}
		string toString() const {
			return folder~'/'~key;
		}
	}
}

unittest {
	string path = "/s/path";
	Parser parser;
	
	foreach(i;11..88) {
		parser.insert(path~"/file"~to!string(i)~".5.cr2");
		parser.insert(path~"/file"~to!string(i)~".7.cr3");
		parser.insert(path~"/file"~to!string(i)~".9.cr2");
	}
	
	for(uint i=20;i<=40;i+=2)
		parser.insert(path~"/file"~to!string(i)~".cr2");
	
	BrowseItem create(string pattern, Range range, uint step){
		return BrowseItem.create_sequence(path, Sequence(parse(pattern), range, step));
	}
	
	auto range = Range(11,87);
	auto expected = [
		create("file##.cr2", Range(20,40),2),
		create("file##.5.cr2", range,1),
		create("file##.9.cr2", range,1),
		create("file##.7.cr3", range,1)
	];
	assert(parser.terminate() == expected);
}

int main(string[] args){
	Parser parser;
	foreach(DirEntry file; dirEntries(args.length==1 ? "." : args[1], SpanMode.shallow))
		parser.insert(file); 
	writeln(parser.terminate());
	return 0;
}