#!/usr/bin/perl -w

if ($#ARGV != 1 ) {
	print "Error: Arguments Missing.";
	exit;
}

print "{\"data\":[";

print "{";
print "\"{#SOURCE}\":\"$ARGV[0]\",";
print "\"{#DEST}\":\"$ARGV[1]\"";
print "}";

print "]}";