import Text "mo:base/Text";
import Char "mo:base/Char";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Path "Path";

module {
    public func match(path : Text, pattern : Text) : Bool {
        // Special case: if pattern is "*" and path is empty, return true
        if (pattern == "*" and path == "") {
            return true;
        };

        let pathSegments = Path.parse(path);
        let patternSegments = Path.parse(pattern);

        // Only enforce absolute path matching if pattern doesn't start with **
        let pathIsAbsolute = Text.startsWith(path, #text "/");
        let patternIsAbsolute = Text.startsWith(pattern, #text "/");

        // If pattern starts with **, allow mixing absolute and relative paths
        if (patternSegments.size() > 0 and patternSegments[0] == "**") {
            return matchSegments(pathSegments, patternSegments, 0, 0);
        };

        // Otherwise, enforce absolute/relative path consistency
        if (pathIsAbsolute != patternIsAbsolute) {
            return false;
        };

        matchSegments(pathSegments, patternSegments, 0, 0);
    };

    private func matchSegments(
        pathSegments : [Text],
        patternSegments : [Text],
        pathIndex : Nat,
        patternIndex : Nat,
    ) : Bool {
        let pathLength = pathSegments.size();
        let patternLength = patternSegments.size();

        // Special case: if both path and pattern are empty, return true
        if (pathLength == 0 and patternLength == 0) {
            return true;
        };

        if (pathIndex == pathLength and patternIndex == patternLength) {
            return true;
        };

        // Special case: if last pattern is "**", it can match end of path
        if (pathIndex == pathLength and patternIndex < patternLength) {
            if (patternIndex == (patternLength - 1 : Nat)) {
                return patternSegments[patternIndex] == "**";
            };
        };

        if (pathIndex >= pathLength or patternIndex >= patternLength) {
            return false;
        };

        let currentPattern = patternSegments[patternIndex];
        let currentPath = pathSegments[pathIndex];

        // Handle "**" pattern specially
        if (currentPattern == "**") {
            // Match zero or more path segments
            return matchSegments(pathSegments, patternSegments, pathIndex, patternIndex + 1) or matchSegments(pathSegments, patternSegments, pathIndex + 1, patternIndex);
        };

        if (matchSegment(currentPath, currentPattern)) {
            return matchSegments(pathSegments, patternSegments, pathIndex + 1, patternIndex + 1);
        };

        false;
    };

    private func matchSegment(segment : Text, pattern : Text) : Bool {
        let segmentChars = segment.chars() |> Iter.toArray(_);
        let patternChars = pattern.chars() |> Iter.toArray(_);
        matchSegmentRecursive(segmentChars, patternChars, 0, 0);
    };
    private type CharSet = {
        ranges : [(Char, Char)];
        chars : [Char];
        negated : Bool;
        length : Nat;
    };

    private func parseCharSet(pattern : [Char], index : Nat) : ?CharSet {
        if (index >= pattern.size() or pattern[index] != '[') {
            return null;
        };

        var pos = index + 1;
        var negated = false;

        // Check for negation
        if (pos < pattern.size() and pattern[pos] == '!') {
            negated := true;
            pos += 1;
        };

        var ranges : [(Char, Char)] = [];
        var chars : [Char] = [];
        var tempChars : [var Char] = [var];
        var length = 0;

        label l loop {
            if (pos >= pattern.size()) {
                break l;
            };

            let c = pattern[pos];
            if (c == ']' and pos > index + 1) {
                // Convert tempChars to immutable array
                chars := Array.tabulate<Char>(length, func(i) { tempChars[i] });
                // Include the closing bracket in length
                return ?{
                    ranges = ranges;
                    chars = chars;
                    negated = negated;
                    length = pos + 1 - index;
                };
            };

            // Check for range pattern
            if (pos + 2 < pattern.size() and pattern[pos + 1] == '-' and pattern[pos + 2] != ']') {
                let start = c;
                let end = pattern[pos + 2];
                ranges := Array.append(ranges, [(start, end)]);
                pos += 3;
                continue l;
            };

            // Add to character set
            let newChars = Array.tabulateVar<Char>(
                length + 1,
                func(i) {
                    if (i < length) { tempChars[i] } else { c };
                },
            );
            tempChars := newChars;
            length += 1;
            pos += 1;
        };

        null;
    };

    private func charMatchesCharSet(c : Char, charSet : CharSet) : Bool {
        // Check if character matches any range
        for ((start, end) in charSet.ranges.vals()) {
            let codePoint = Char.toNat32(c);
            let startPoint = Char.toNat32(start);
            let endPoint = Char.toNat32(end);
            if (codePoint >= startPoint and codePoint <= endPoint) {
                return if (charSet.negated) false else true;
            };
        };

        // Check if character matches any individual char
        for (setChar in charSet.chars.vals()) {
            if (c == setChar) {
                return if (charSet.negated) false else true;
            };
        };

        // No match found
        if (charSet.negated) true else false;
    };

    private func matchSegmentRecursive(
        segment : [Char],
        pattern : [Char],
        segmentIndex : Nat,
        patternIndex : Nat,
    ) : Bool {
        if (segmentIndex == segment.size() and patternIndex == pattern.size()) {
            return true;
        };

        if (segmentIndex > segment.size() or patternIndex >= pattern.size()) {
            if (patternIndex < pattern.size()) {
                return pattern[patternIndex] == '*' and matchSegmentRecursive(segment, pattern, segmentIndex, patternIndex + 1);
            };
            return false;
        };

        // Handle escaped characters
        if (patternIndex + 1 < pattern.size() and pattern[patternIndex] == '\\') {
            if (segmentIndex < segment.size() and segment[segmentIndex] == pattern[patternIndex + 1]) {
                return matchSegmentRecursive(segment, pattern, segmentIndex + 1, patternIndex + 2);
            };
            return false;
        };

        // Check for character set or range
        switch (parseCharSet(pattern, patternIndex)) {
            case (?charSet) {
                if (segmentIndex < segment.size() and charMatchesCharSet(segment[segmentIndex], charSet)) {
                    return matchSegmentRecursive(segment, pattern, segmentIndex + 1, patternIndex + charSet.length);
                };
                return false;
            };
            case null {
                switch (pattern[patternIndex]) {
                    case ('*') {
                        matchSegmentRecursive(segment, pattern, segmentIndex + 1, patternIndex) or matchSegmentRecursive(segment, pattern, segmentIndex, patternIndex + 1);
                    };
                    case ('?') {
                        if (segmentIndex < segment.size()) {
                            matchSegmentRecursive(segment, pattern, segmentIndex + 1, patternIndex + 1);
                        } else {
                            false;
                        };
                    };
                    case (patternChar) {
                        if (segmentIndex < segment.size() and segment[segmentIndex] == patternChar) {
                            matchSegmentRecursive(segment, pattern, segmentIndex + 1, patternIndex + 1);
                        } else {
                            false;
                        };
                    };
                };
            };
        };
    };
};
