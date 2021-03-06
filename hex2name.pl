#!/usr/bin/perl

# jr-resolve.pl - convert timing lib output addresses to names
# hacked from cyg-profile script found on web.

use strict;
use warnings;
no warnings 'portable';
use diagnostics;
use English;

my (%symtab);    # symbol table derived from executable
my ($binfile);   # executable
my ($timingout); # timer file (normally timing.[0-9]*)
my ($demangle);  # whether to demangle the symbols
my ($arg);       # cmd-line arg
my ($PRTHRESH) = 1000000; # This needs to match what is in the GPTL lib
our ($max_sym) = 0;

$OUTPUT_AUTOFLUSH = 1;

&help() if ($#ARGV < 1 || $#ARGV > 2);

while ($arg = shift (@ARGV)) {
    if ($arg eq "-demangle") {
	$demangle = 1;
    } elsif ( ! defined ($binfile)) {
	$binfile = $arg;
    } else {
	$timingout = $arg;
    }
}

&help() if ($binfile =~ /--help/);
&help() if (!defined ($binfile));
&help() if (!defined ($timingout));

&main();

# ==== Subs

sub help()
{
    printf ("Usage: $0 [-demangle] executable timing_file\n");
    exit;
}

sub main()
{
    my ($offset);    # offset into a.out (to match timing output)
    my ($type);      # symbol type
    my ($function);  # name of function in symtab
    my ($nsym) = 0;  # number of symbols
    my ($nfunc) = 0; # number of functions
    my ($spaftsym);
	
    if ($demangle) {
	open (NM, "nm $binfile | c++filt | ") or die ("Unable to run 'nm $binfile | c++filt': $!\n");
    } else {
	open (NM, "nm $binfile |") or die ("Unable to run 'nm $binfile': $!\n");
    }

    printf ("Loading symbols from $binfile ... ");
	
    while (<NM>) {
	$nsym++;
	next if (!/^([0-9A-F]+) (.) (.+)$/i);
	$offset   = hex($1); 
	$type     = $2; 
	$function = $3;
	next if ($type !~ /[tT]/);
	$nfunc++;
	$symtab{$offset} = $function;
    }
    printf("OK\nSeen %d symbols, stored %d function offsets\n", $nsym, $nfunc);
    close(NM);


    if ($timingout eq "timing.summary") {
	&parse_and_print_summary ();
    } else {
	&parse_and_print ("$timingout");
    }
}

sub parse_and_print ()
{
    my ($file) = $_[0];
    my ($statsforthread) = 0;    # Inside region "Stats for thread ..."
    my ($sortedbytimer) = 0;     # Inside region "Same stats sorted by ..."
    my ($countnexttochild) = 0;  # Inside region "Count next to child ..."
    my ($thread) = -1;           # thread number (init to -1
    my ($spaces);                # text containing spaces before rest of line
    my ($numsp);                 # number of spaces before rest of line
    my ($begofline);
    my ($indent);
    my ($off1);
    my ($ncalls);
    my ($restofline);
    my ($sym);       # symbol
    my (@max_chars);             # longest symbol name + indentation (per thread)

    @max_chars = &get_max_chars ("$file");
    open (TEXT, "<$file") or die ("Unable to open '$file': $!\n");
    while (<TEXT>) {

	# 3 types of input line will need parsing
	
	if (/^Stats for thread /) { # beginning of main region
	    $statsforthread = 1;
	    $sortedbytimer = 0;
	    $countnexttochild = 0;
	    ++$thread;
	    print $_; 
	    next;
	} elsif (/^(Thd)       (Called.*)$/) {  # Sorted by timer
	    $statsforthread = 0;
	    $sortedbytimer = 1;
	    $countnexttochild = 0;
	    $spaces = " " x $max_sym;
	    printf ("%s%s%s\n", $1, $spaces, $2);
	    next;
	} elsif (/^Count next to child /) {  # Parent-child stats
	    $statsforthread = 0;
	    $sortedbytimer = 0;
	    $countnexttochild = 1;
	    print $_; 
	    next;
	} elsif ( ! $statsforthread && ! $sortedbytimer && ! $countnexttochild) {  # header--just print
	    print $_; 
	    next;
	}

	if ($statsforthread) {
	    if (/^ *(Called  Recurse.*)$/) { # heading
		$numsp = $max_chars[$thread];
		$spaces = " " x $numsp;
		printf ("%s   %s\n", $spaces, $1);
	    } elsif (/(^\*? *)([[:xdigit:]]+)( +)([0-9.Ee+]+)(.*)$/) { # hex entry
		$begofline  = $1;
		$off1       = hex($2);
		$ncalls     = $4;
		$restofline = $5;
		if (defined ($symtab{$off1})) {
		    $sym = $symtab{$off1};
		} else {
		    $sym = "???";
		}
		$numsp = $max_chars[$thread] - length ($begofline) - length ($sym);
		$spaces = " " x $numsp;
		printf ("%s%s%s %9s %s\n", $begofline, $sym, $spaces, $ncalls, $restofline);
	    } elsif (/(^\*? *)(\w+)( +)([0-9.Ee+]+)(.*)$/) { # standard entry
		$begofline  = $1;
		$sym        = $2;
		$ncalls     = $4;
		$restofline = $5;
		$numsp = $max_chars[$thread] - length ($begofline) - length ($sym);
		$spaces = " " x $numsp;
		printf ("%s%s%s %9s %s\n", $begofline, $sym, $spaces, $ncalls, $restofline);
	    } else {           # unknown: just print it
		print $_; 
	    }
	} elsif ($sortedbytimer) {
	    if (/^([0-9][0-9][0-9] )([[:xdigit:]]+)( +)(.*)$/ ||
		/^(SUM )([[:xdigit:]]+)( +)(.*)$/) {
		$off1 = hex($2);
		if (defined ($symtab{$off1})) {
		    $sym = $symtab{$off1};
		} else {
		    $sym = "???";
		}
		$numsp = length($3) + $max_sym - length ($sym) - 1;
		$spaces = " " x $numsp;
		printf ("%s%s%s%s\n", $1, $sym, $spaces, $4);
	    } else {
		print $_;
	    }
	} elsif ($countnexttochild) {
	    if (/(^ *)([0-9.Ee+]+)( +)([[:xdigit:]]+)( *)$/) {
#
# Hex entry in multiple parent region
#
		$ncalls     = $2;
		$indent     = $3;
		$off1       = hex($4);
		if (defined ($symtab{$off1})) {
		    $sym = $symtab{$off1};
		} else {
		    $sym = "???";
		}
		$restofline = $5;
		printf ("%8s%s%s%s\n", $ncalls, $indent, $sym, $restofline);
	    } else { # unknown: just print it
		print $_; 
		next;
	    }
	}
    }
    close (TEXT);
    printf("done\n");
}

sub parse_and_print_summary ()
{
    my ($restofline);
    my ($addsp);
    my ($spaces);
    my ($off1);
    my ($sym);       # symbol
    my ($mc);
    my ($num);       # first number after name

    $mc = &get_max_chars_summary ("timing.summary");

    open (TEXT, "<timing.summary") or die ("Unable to open 'timing.summary': $!\n");
    while (<TEXT>) {
	if (/^name *(ncalls nranks mean_time.*)$/) { # beginning of main region
	    $addsp = $mc - 4;   # subtract length of "name"
	    $spaces = " " x $addsp;
	    printf ("name %s %s\n", $spaces, $1);
	} elsif (/(^[[:xdigit:]]+) *([0-9.Ee+]+)(.*)$/) { # hex entry
	    $off1       = hex($1);
	    $num        = $2;
	    $restofline = $3;
	    if (defined ($symtab{$off1})) {
		$sym = $symtab{$off1};
	    } else {
		$sym = "???";
	    }
	    $addsp = $mc - length ($sym);
	    if ($addsp > 0) {
		$spaces = " " x $addsp;
	    } else {
		$spaces = "";
	    }
	    printf ("%s %s%7s%s\n", $sym, $spaces, $num, $restofline);
	} elsif (/^([a-zA-Z0-9_]+) *([0-9.Ee+]+)(.*)$/) {     # standard entry
	    $num        = $2;
	    $restofline = $3;
	    $addsp = $mc - length ($1);
	    if ($addsp > 0) {
		$spaces = " " x $addsp;
	    } else {
		$spaces = "";
	    }
	    printf ("%s %s%7s%s\n", $1, $spaces, $num, $restofline);
	} else {           # unknown: just print it
	    print $_; 
	}
    }
    close (TEXT);
    printf("done\n");
}

sub get_max_chars ()
{
    my ($file) = $_[0];
    my ($thread) = -1;
    my ($tmp);
    my ($sym);
    my ($off1);
    my ($doparse) = 0;
    my ($lensym);
    my (@max_chars);
    our ($max_sym) = 0;
    
    open (TEXT, "<$file") or die ("Unable to open '$file': $!\n");
    while (<TEXT>) {

	# Parse the line if it's a hex number followed by a number
	
	if (/Stats for thread /) {
	    $doparse = 1;
	    ++$thread;
	    $max_chars[$thread] = 0;
	} elsif (/^Total calls /) {
	    $doparse = 0;
	} elsif ($doparse && /(^\*? *)([[:xdigit:]]+)/) {
	    $off1 = hex($2);
	    if (defined ($symtab{$off1})) {
		$sym = $symtab{$off1};
	    } else {
		$sym = "???";
	    }
	    $lensym = length ($sym);
	    $tmp = length ($1) + $lensym;
	    if ($tmp > $max_chars[$thread]) {
		$max_chars[$thread] = $tmp;
	    }
	    if ($lensym > $max_sym) {
		$max_sym = $lensym;
	    }
	}
    }
    close (TEXT);
    return @max_chars;
}

sub get_max_chars_summary ()
{
    my ($file) = $_[0];
    my ($sym);
    my ($off1);
    my ($lensym);
    my ($max_chars) = 0;
    
    open (TEXT, "<$file") or die ("Unable to open '$file': $!\n");
    while (<TEXT>) {

	# Parse the line if it's a hex number followed by a number
	
	if (/(^[[:xdigit:]]+) +(.*)$/) {
	    $off1 = hex($1);
	    if (defined ($symtab{$off1})) {
		$sym = $symtab{$off1};
	    } else {
		$sym = "???";
	    }
	    $lensym = length ($sym);
	    if ($lensym > $max_chars) {
		$max_chars = $lensym;
	    }
	}
    }
    close (TEXT);
    return $max_chars;
}
