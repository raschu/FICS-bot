use strict;
use warnings;
use Sys::Hostname;
use FileHandle;
use IPC::Open2;
use Term::ANSIColor;
use Config::IniFiles;

our $cfg = new Config::IniFiles( -file => "./bot.ini" );

our $VERSION = "1.0.8";

our $timeseal = $cfg->val('Globals','Timeseal');
our $engine   = $cfg->val('Globals','Engine');
our $operator = $cfg->val('Globals','Operator');
our $maxgames = $cfg->val('Globals','MaxGames');; #Anzahl Spiele, dann gibts einen Logout
our $seek1    = $cfg->val('Globals','Seek1');
our $seek2    = $cfg->val('Globals','Seek2');
our $seek3    = $cfg->val('Globals','Seek3');

#our $engine = "/Users/ralph/Library/SchachEngines/toga/TogaII-MacIntel";
#our $engine = "/Users/ralph/Library/SchachEngines/fruit/fruit221";
#our $timeseal = "/Users/ralph/Desktop/Groubian/timeseal freechess.org 5000";

our $myhandle = "";
our $mycolor;
our $movecounter = 0;
our $playedgames = 0;
our $quit = 0;
our $machine = hostname();
our $perlversion = sprintf "%vd", $^V;
our $osstring = $^O;

our $tspid = open2(*TSReader,*S,$timeseal);

open(LOGIN,"./FICSlogin.txt") or die ("cannot open: $!");
my @loginscript = <LOGIN>;
close(LOGIN);

foreach (@loginscript) {
	chop($_);
	print S "$_\n";
}
print S "set interface $engine (Perl: $perlversion  OS: $osstring  Host: $machine)\n";
print S "$seek1\n";
print S "$seek2\n";
print S "$seek3\n";
 
startengine();
#-----------------------------------------------
while(<TSReader>) { #Main Loop
#-----------------------------------------------	
	#$linecnt++;
	$_ =~ s/[\n]//g; #read a line
	
	my $lastLine=$_;
	$lastLine =~ s/^.//;
	
	print color 'yellow';
	print "$lastLine\n";
	print color 'reset';
	
	if ($lastLine =~ m/tells you/) {
		respondtell($lastLine);
		next;
	}
	if ($lastLine =~ m/Finger of /) {
		$myhandle = $lastLine;
		$myhandle =~ s/fics% Finger of //;
		$myhandle =~ s/\://;
		$myhandle =~ s/\(U\)//;
		$myhandle =~ s/\(C\)//;
		print "My Handle is $myhandle\n";
		next;
	}
	if ($lastLine =~ m/<12>/) { #style 12 wurde ausgeführt
		my @styledata = split(/ /, $lastLine);
		my $colortomove = lc($styledata[9]);
		makeamove($lastLine) if $mycolor eq $colortomove;
		next;
	}	
	if ($lastLine =~ m/Creating: /) {
		$playedgames++;
		print S "tell $operator New game started ($playedgames of $maxgames)\n";
		my @gamedata = split(/ /,$lastLine);
		if ($gamedata[1] eq $myhandle) {
			$mycolor = "w";
		} else {
			$mycolor = "b";
		}
		$movecounter = 0;
		next;
	}
	if ($lastLine =~ m/ rating adjustment / or $lastLine =~ m / ratings adjustment /) {
		if ($quit == 1) {
			print S "exit\n";
			system("osascript ./ruhezustand.scpt");
			exit;
		}
		if ($playedgames >= $maxgames) {
			print S "exit\n";
			system("osascript ./ruhezustand.scpt");
			exit;
		}
		print S "$seek1\n";
		print S "$seek2\n";
		print S "$seek3\n";
		next;
	}	
	if ($lastLine =~ m/Your opponent has aborted/ or $lastLine =~ m/lost connection and too few moves; game aborted/) {
		print S "$seek1\n";
		print S "$seek2\n";
		print S "$seek3\n";
	}
}
#-----------------------------------------------
sub makeamove {
#-----------------------------------------------	
	my $s12string = shift;
	my $fen;
	my $multipv;
	my $wtime;
	my $btime;
	my $winc;
	my $binc;
	
	if ($movecounter == 0) {
		print S "d2d4\n";
		$movecounter++;
		return;
	}
	$fen = convs12tofen($s12string);
	($wtime, $btime, $winc, $binc) = remaintime($s12string);
	print "Debug: $wtime, $btime, $winc, $binc\n";
	#print "FEN to Engine: $fen\n";
	print Engine "position fen $fen\n";
	#print Engine "go movetime 10000\n";
	print Engine "go wtime $wtime btime $btime winc $winc binc $binc\n";
	while (<Reader>) {
		my $line = $_;
		#chop($line);
		
		$line =~ s/\n|\r//g;
		
		if ($line =~ m/multipv/) {
			print color 'red';
	    print "$line\n";
	    print color 'reset';
			$multipv = $line;
		} else {
			#print "$line\n";
		}
		if ($line =~ m/bestmove /) {
			my @bmarray = split(/ /,$line);
			my $bestmove = $bmarray[1];
			if (length($bestmove) > 4) {
				my $umwandler = substr($bestmove,4,1);
				$bestmove = substr($bestmove,0,4);
				$bestmove = "$bestmove"."="."$umwandler";
			}
			print "Debug: $bestmove\n";
			
			my @pvdata = split(/ /,$multipv);
			
			print S "$bestmove\n";
			#print S "tell $operator $pvdata[8] $pvdata[9] --> $pvdata[16]\n";
			print S "whisper $pvdata[8] $pvdata[9] --> $pvdata[16]\n";
			last;
		}
	}
}
#-----------------------------------------------
sub remaintime {
#-----------------------------------------------	
	my $s12 = shift;
	my @s12data = split(/ /,$s12);
	my $wtime;
	my $btime;
	my $winc;
	my $binc;
	
	$wtime = $s12data[24] * 1000;
	$btime = $s12data[25] * 1000;
	$winc = $s12data[21] * 1000;
	$binc = $s12data[21] * 1000;
	
	return ($wtime, $btime, $winc, $binc);
}
#-----------------------------------------------
sub respondtell {
#-----------------------------------------------	
	my $tell = shift;
	my ($nick, $dummy1, $dummy2, $arg1, $arg2, $arg3) = split(/ +/,$tell);
	
	if ($dummy1 eq "tells" and $dummy2 eq "you:") { #wirklich nur bei eigenen Tells, nicht als 
		
		if ($arg1 eq "scoreaaaaaaaa") {
			#makenothing;
		} elsif ($arg1 eq "help") {
			tellhelp($nick);
		}	 elsif ($arg1 eq "quit") {
			tellquit($nick);
		}	else {
			tellunknown($nick, $arg1);
		}
	}
}
#-----------------------------------------------
sub tellquit {
#-----------------------------------------------	
	my $nick = shift;
	if ($nick eq $operator) {
			print S "tell $nick Ok. I'll quit after the next game ending\n";
			$quit = 1;
	}
}
#-----------------------------------------------
sub tellhelp {
#-----------------------------------------------	
	my $nick = shift;
	print S "tell $nick Sorry, nohelp\n";
}
#-----------------------------------------------
sub tellunknown {
#-----------------------------------------------	
	my $nick = shift;
	my $command = shift;
	print S "tell $nick Sorry $nick, I don't know this command: $command\n";
}
#-----------------------------------------------
sub startengine {
#-----------------------------------------------	
	my $count = 0;
	our $pid = open2(*Reader,*Engine,$engine);
	while (<Reader>) {
		
		my $line = $_;
		#chop($line);
		$line =~ s/\n|\r//g;

		if ($count == 0) {
			print Engine "uci\n";
			$count++;
		}	
			
		if ($line eq "uciok") {
			print Engine "isready\n";
			print "Engine is ready\n";
			print S "tell $operator Engine is ready\n";
		}
		if ($line eq "readyok") {
			print Engine "ucinewgame\n";
			print Engine "setoption name UCI_AnalyseMode value true\n";
			print Engine "setoption name OwnBook value true\n";
			last;
		}
	}
}
#-----------------------------------------------
sub convs12tofen {
#-----------------------------------------------	
	my $s12 = shift;
	my @s12data = split(/ /,$s12);

	print "-------------------------------\n";

	my $r8 = $s12data[1];
	my $r7 = $s12data[2];
	my $r6 = $s12data[3];
	my $r5 = $s12data[4];
	my $r4 = $s12data[5];
	my $r3 = $s12data[6];
	my $r2 = $s12data[7];
	my $r1 = $s12data[8];
	
	my $colortomove = lc($s12data[9]);
	my $anzahlhalbzuege = $s12data[15];
	my $movenumber = $s12data[26];
	my $doublepawnmove = $s12data[10];
	
	if ($doublepawnmove != -1) {
		my $line;
		my $reihe;
		if ($colortomove eq "w") {
			$line = 6;
		} else {
			$line = 3;
		}
		$reihe = "a" if $doublepawnmove == 0;
		$reihe = "b" if $doublepawnmove == 1;
		$reihe = "c" if $doublepawnmove == 2;
		$reihe = "d" if $doublepawnmove == 3;
		$reihe = "e" if $doublepawnmove == 4;
		$reihe = "f" if $doublepawnmove == 5;
		$reihe = "g" if $doublepawnmove == 6;
		$reihe = "h" if $doublepawnmove == 7;
		
		$doublepawnmove = "$reihe"."$line";
	}

	
	#######################Rochade####################
	
	my $castle = "";
	
	my $whscastle = $s12data[11];
	my $whlcastle = $s12data[12];
	my $blscastle = $s12data[13];
	my $bllcastle = $s12data[14];
	
	if ($whscastle == 1) {
		$castle = "$castle"."K";
	}
	if ($whlcastle == 1) {
		$castle = "$castle"."Q";
	}
	if ($blscastle == 1) {
		$castle = "$castle"."k";
	}	
	if ($bllcastle == 1) {
		$castle = "$castle"."q";
	}
	
	$castle = "-" if $castle eq "";
	
	##################################################

	$r8 = convert($r8);
	$r7 = convert($r7);
	$r6 = convert($r6);
	$r5 = convert($r5);
	$r4 = convert($r4);
	$r3 = convert($r3);
	$r2 = convert($r2);
	$r1 = convert($r1);

	return "$r8/$r7/$r6/$r5/$r4/$r3/$r2/$r1 $colortomove $castle $doublepawnmove $anzahlhalbzuege $movenumber";
}
#-----------------------------------------------
sub convert {
#-----------------------------------------------	
	my $string = shift;
	my @values = split(//,$string);
	if ($string !~ m/-/) {
		return $string;
	}
	$string =~ s/-/9/g;
	my @splitted = split(/\D/,$string);
	
	foreach (@splitted) {
		my $length = length($_);
		$string =~ s/9+/$length/ if $length > 0;
	}
	return "$string";
}

