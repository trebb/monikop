#! /usr/bin/perl
use strict;
use warnings;
#use diagnostics;
use Data::Dumper;
use File::Rsync;
use Thread 'async';
use threads::shared;
use Curses;

my @pokinom_banner = (
    "    _/_/_/      _/_/    _/    _/  _/_/_/  _/      _/    _/_/    _/      _/ ",
    "   _/    _/  _/    _/  _/  _/      _/    _/_/    _/  _/    _/  _/_/  _/_/  ",  
    "  _/_/_/    _/    _/  _/_/        _/    _/  _/  _/  _/    _/  _/  _/  _/   ",  
    " _/        _/    _/  _/  _/      _/    _/    _/_/  _/    _/  _/      _/    ",  
    "_/          _/_/    _/    _/  _/_/_/  _/      _/    _/_/    _/      _/     "
    );
	
########################################
# Global defaults
########################################
my $debug = 0; # 0 = clean UI; 1 = lots of scrolling junk; anything else = both (pipe to file)

# Possible mount points. Must be unique in their tails after rightmost /.
@possible_mount_points = ('/root/tt6', '/root/tt7', '/root/tt8');
# Directory where new data is in.
$path_under_mount_point = 'measuring_data';
# Directories of this name will be deleted.
$path_under_mount_point_backed_up = 'backed_up';
# Directory name while being deleted by monikop.
$path_under_mount_point_being_deleted = 'being_deleted';
# Data sink.
$destination = 'vvastr164::ftp/NEW_DATA';
# Rsync credentials.
$rsync_username = 0;
$rsync_password = 0;
# Full path to rsync's raw log
$rsync_log_prefix = '/root/log.';
# Shut down when finished? (default) 0 = no, 1 = yes
$shut_down_when_finished = 0;
# How to turn off
$shut_down_action = "touch shut_down_requested";

# Local changes to the above.
do "pokinom.config";

# Places for running rsyncs to put their runtime info in
my %speeds :shared;
my %progress_ratios :shared;
my %done :shared;
my $shut_down_when_done :shared = $shut_down_when_finished;

sub debug_print { if ($debug) { print @_; } };

# Return sorted intersection of arrays which are supposed to have unique
# elements.
sub intersection {
    my @intersection = ();
    my %count = ();
    my $element;
    foreach $element (@_) { $count{$element}++ }
    foreach $element (keys %count) {
	push @intersection, $element if $count{$element} > 1;
    }
    sort @intersection;
}

sub rsync_preparation_form {
    my ($source) = @_;
    join ( '',
	   "\n",
##########  Capture rsync's status messages for usage by a GUI
	   '$rsync_outfun_', $source, ' = sub {',
	   '    my ($outline, $outputchannel) = @_ ; ',
	   '    my ($speed) = $outline =~ /\d+\s+\d+%\s+(\S+)/; ',
	   '    my ($progress_ratio) = $outline =~ /.+to-check=(\d+\/\d+)\)$/; ',
	   '    if ($speed and $outputchannel eq \'out\') {',
	   '        $speeds{\'', $source, '\'} = $speed;',
	   '    } else {',
	   '        $speeds{\'', $source, '\'} = " -";',
	   '    };',
	   '    if ($progress_ratio and $outputchannel eq \'out\') {',
	   '        $progress_ratios{\'', $source, '\'} = $progress_ratio;',
	   '    } ;',
	   '};',
	   "\n",
##########  Run rsync
	   '$rsync_', $source, ' = File::Rsync->new; ',
##########  Return fodder for another eval
	   '$rsync_exec_form{\'', $source, '\'} = sub {',
	   '    \'$rsync_', $source, '->exec(',
	   '        {',
	   '            src => \\\'', $source_roots{$source}, '/', $path_under_mount_point, '/\\\', ',
	   '            dest => \\\'' . $destination . '/\\\', ',
	   '            outfun => $rsync_outfun_', $source, ', ', 
	   '            progress => 1, debug => 0, verbose => 0, ',
	   '            literal => [\\\'--recursive\\\', \\\'--times\\\', ',
	   '                        \\\'--prune-empty-dirs\\\', ',
	   '                        \\\'--log-file-format=%i %b %n\\\', ',
	   '                      , \\\'--log-file=', $rsync_log_prefix, $source, '\\\'] ',
	   '        }',
	   '    );\' ',
	   '};',
	   "\n",
	)};

sub act_on_keypress {
    my ($pressed_key) = @_;
    if ($pressed_key eq 267) { qx($shut_down_action); }
    elsif ($pressed_key eq 273) { # F9
	$shut_down_when_done = $shut_down_when_done ? 0 : 1; }
}

$ENV{USER} = $rsync_username if ($rsync_username);
$ENV{RSYNC_PASSWORD} = $rsync_password if ($rsync_password);

# Preparations done; sleeves up!

# Find usable (i.e. mounted) sources
@raw_mount_points = grep (s/\S+ on (.*) type .*/$1/, qx/mount/);
chomp @raw_mount_points;
@source_roots = intersection @raw_mount_points, @possible_mount_points;
debug_print "SOURCE_ROOTS:\n";
debug_print @source_roots;
# TODO: perhaps use whole string for key
grep {
    my $key = $_; $key =~ s/\S+(\/|:|::)(\w+)$/$2/; $source_roots{$key} = $_
} @source_roots;
print %source_roots;
# Clean up sources if necessary
map {
    my $p_i_d = $source_roots{$_} . '/' . $path_under_mount_point;
    my $p_i_d_being_deleted =  $source_roots{$_} . '/' . $path_under_mount_point_being_deleted;
    $being_deleted_thread{$_} = async { qx(rm -rf $p_i_d_being_deleted 2> /dev/null); };
} keys %source_roots;

# Set up and start things per source_root:
map {
    $progress_ratios{$_} = "?"; # Initialize for UI
    $done{$_} = 0;
    $rsync_worker_thread{$_} = async {
	my $rsync_log_name = $rsync_log_prefix . $_;
	debug_print 'rsync_preparation_form:' . rsync_preparation_form ($_). "\n";
	eval rsync_preparation_form $_;
	debug_print "EVAL RSYNC_PREPARATION_FORM $_: $@ \n";
	my $complete_source = $source_roots{$_} . '/' . $path_under_mount_point;
	my $complete_source_backed_up = $source_roots{$_} . '/' . $path_under_mount_point_backed_up;
	if (-d $complete_source) {
	    if (eval ($rsync_exec_form{$_}() )) {
		debug_print "EVAL RSYNC_EXEC_FORM (successful) $complete_source: $@ \n";
		qx(mv $complete_source $complete_source_backed_up);
	    } else {
		die "EVAL RSYNC_EXEC_FORM (failed) $complete_source: $@ \n";
	    }
	}
	$progress_ratios{$_} = "Done";
	$speeds{$_} = "-";
	$done{$_} = 1;
	unlink $rsync_log_name unless $debug;
    }
} keys %source_roots;

if ($debug == 1) {
# Let the workers toil.
    sleep;
} else {
# Let the workers toil and talk to the user.
    initscr();
    cbreak();
    noecho();
    curs_set(0);
    my $window_top = newwin(LINES() - 8, 79, 0, 0);
    my $window_center = newwin(5, 79, LINES() - 8, 0);
    my $window_bottom = newwin(3, 79, LINES() - 3, 0);
    my $window_bottom->keypad(1);
    my $window_bottom->nodelay(1);
    start_color;
    init_pair 1, COLOR_MAGENTA, COLOR_BLACK;
    init_pair 2, COLOR_RED, COLOR_BLACK;
    init_pair 3, COLOR_CYAN, COLOR_BLACK;
    init_pair 4, COLOR_YELLOW, COLOR_BLACK;
    my $MAGENTA = COLOR_PAIR(1);
    my $RED = COLOR_PAIR(2);
    my $CYAN = COLOR_PAIR(3);
    my $YELLOW = COLOR_PAIR(4);
    while (1) {
	$window_top->attron($CYAN);
	$window_top->box(0,0);
	$window_top->addstr(0, 30, " P r o g r e s s ");
	$window_top->attroff($CYAN);
	my $sources_format = "%-25s%-18s%-8s";
	$window_top->attron(A_BOLD);
	$window_top->addstr(1, 12,
			      sprintf ($sources_format,
				       "Source Medium", "Speed", "To Do"));
	$window_top->attroff(A_BOLD);
	$line_number = 2;
	map {
	    my $source = $_;
	    $window_top->attron($CYAN);
	    $window_top->attron($RED) if $done{$source};
	    $window_top->addstr($line_number, 12,
				  sprintf($sources_format,
					  substr($source . $source_roots{$source}, 0, 24),
					  substr($speeds{$source}, 0, 17),
					  substr($progress_ratios{$source}, -8, 8)));
	    ++ $line_number;
	    $window_top->addstr($line_number, 1,
				  sprintf($sources_format, "", "", "", ""));
	    $window_top->attroff($RED);
	    $window_top->attroff($CYAN);
	} sort (keys %source_roots);
	$line_number = 0;
#	$window_center->attron(A_BOLD);
	map {
	    $window_center->addstr($line_number, 2, $_);
	    ++ $line_number;
	} @pokinom_banner;
#	$window_center->attroff(A_BOLD);

	$window_bottom->box(0,0);
	$window_bottom->attron(A_BOLD);
	$window_bottom->addstr(1, 3,
			       sprintf ("[F3]: Turn off now.%54s",
			       $shut_down_when_done ? "Turning off when done.  [F9]: Stay on."
					: "Staying on.  [F9]: Turn off when done."));
	$window_bottom->attroff(A_BOLD);

	$window_top->refresh();
	$window_center->refresh();
	$window_bottom->refresh();
	sleep 2;
	act_on_keypress($window_bottom->getch());
	if (! grep(/0/, values %done) && $shut_down_when_done) {
	    qx ($shut_down_action);
	}
    }
    endwin();
}


# Tidy up. (Except we don't reach this.)
map {
    $being_deleted_thread{$_}->join if $being_deleted_thread{$_};
} @source_roots;

map {
    $rsync_worker_thread{$_}->join if $rsync_worker_thread{$_};
} @source_roots;

