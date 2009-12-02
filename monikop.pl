#! /usr/bin/perl
#use strict;
use warnings;
#use diagnostics;
use Data::Dumper;
#use List::Util qw/max min sum/;
#use Proc::ProcessTable;
#use Proc::Killfam;
#use Net::Ping;
#use Cwd 'realpath';
#use Fcntl ':flock'; 
use Fcntl 'SEEK_SET'; 
#use Filesys::Df;
use File::Rsync;
#use File::Touch;
#use File::stat;
#use File::Copy;
#use File::Spec::Functions qw/splitpath catfile/;
#use XML::Simple;
use Thread 'async';
use threads;
use threads::shared;
use Curses;

@monikop_ad = (
    "    _/      _/    _/_/    _/      _/  _/_/_/  _/    _/    _/_/    _/_/_/   ", 
    "   _/_/  _/_/  _/    _/  _/_/    _/    _/    _/  _/    _/    _/  _/    _/  ",
    "  _/  _/  _/  _/    _/  _/  _/  _/    _/    _/_/      _/    _/  _/_/_/     ", 
    " _/      _/  _/    _/  _/    _/_/    _/    _/  _/    _/    _/  _/          ", 
    "_/      _/    _/_/    _/      _/  _/_/_/  _/    _/    _/_/    _/           "
    );
	
########################################
# Global defaults
########################################
$debug = 0; # 0 = clean UI; 1 = lots of scrolling junk
# Possible mount points. Must be unique.
@usable_mount_points = ('/root/tt6', '/root/tt7', '/root/tt8', '/blah');
# Directory to put new data in.
$path_in_destination = 'measuring_data';
# A directory of this name will be deleted.
$path_in_destination_backed_up = 'backed_up';
# Directory name while being deleted.
$path_in_destination_being_deleted = 'being_deleted';
# Directory inside $path_in_destination where rsync stores unfinished files
$rsync_tempdir_prefix = '.rsync_temp_';
# Possible data sources.
%source_roots = ('tt11' => '/log', 'tt10' => '/log', 'tt9' => '/log', 'vvastr164' => '::ftp');
#%source_roots = ('tt11' => '/log');
# Full path to rsync's raw log
$rsync_log_prefix = '/root/log.';
# Full path to list of successfully rsynced files.
$finished_prefix = '/root/finished_'; 
# How to name the duplicate of a safe file.
$safe_file_backup_suffix = '_bak'; 
# Name of a safe file wannabe.
$safe_file_unfinished_suffix = '_unfinished'; 
# What to do when F3 has been pressed
$key_f3_action = "touch f3_pressed";
# What to do when F6 has been pressed
$key_f6_action = "touch f6_pressed";
$coffee_break = 10; # Time in seconds before rsync gets restarted.

# Local changes to the above.
do "monikop.config";

# Places for running rsyncs to put their runtime info in
my %speeds :shared;
my %progress_ratios :shared;
# Other information
my %destination_usages :shared;
my %destination_usage_ratios :shared;
my %destination_source_is_writing_to :shared;

sub debug_print { if ($debug) { print @_; } };

# Return sorted intersection of arrays which are supposed to have unique
# elements.
sub intersection {
    my @intersection = ();
    my %count = ();
    foreach $element (@_) { $count{$element}++ }
    foreach $element (keys %count) {
	push @intersection, $element if $count{$element} > 1;
    }
    sort @intersection;
}

# Write @content to a file with a name starting with $filename
# and ending with _a or _b. Leave at least one such file, even if interrupted.
sub safe_write {
    my ($filename, @content) = @_;
    my $filename_a = $filename;
    my $filename_b = $filename . $safe_file_backup_suffix;
    my $filename_unfinished = $filename . $safe_file_unfinished_suffix;
    local (*FILE_UNFINISHED);
    open FILE_UNFINISHED, '>', $filename_unfinished or die "[" . $$ . "] open $filename_unfinished failed: $!\n";
    print FILE_UNFINISHED @content;
    close FILE_UNFINISHED;
    qx(cp $filename_unfinished $filename_b);
    qx(mv $filename_unfinished $filename_a);
}

sub reassure_safe_file {
    my ($filename) = @_;
    my $filename_a = $filename;
    my $filename_b = $filename . $safe_file_backup_suffix;
    qx(touch $filename_a);
    if (stat $filename_b) {
	qx(cp $filename_b $filename_a)
    }
}

# Put contents of $filename into an array.
sub read_list {
    my ($filename) = @_;
    local (*FILE);
    open FILE, '<', $filename or warn "[" . $$ . "] open $filename failed: $!\n";
    my @value = <FILE>;
    close FILE;
    @value;
}

sub safe_read {
    my ($filename) = @_;
    my $filename_a = $filename;
    my $filename_b = $filename . $safe_file_backup_suffix;
    if (stat $filename_a) { my $filename = $filename_a }
    elsif (stat $filename_b) { my $filename = $filename_b }
    else { return () }
    debug_print "SAFE_READ: $filename";
    read_list $filename;
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
	   '        $speeds{\'', $source, '\'} = " ---";',
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
	   '    my ($complete_destination) = @_;',
	   '    \'$rsync_', $source, '->exec(',
	   '        {',
	   '            src => \\\'', $source, $source_roots{$source}, '/\\\', ',
	   '            dest => \\\'\' . $complete_destination . \'/\\\', ',
	   '            outfun => $rsync_outfun_', $source, ', ', 
	   '            progress => 1, debug => 0, verbose => 0, ',
	   '    	filter => [\\\'merge,- ', $finished_prefix, $source, '\\\'], ',
	   '            literal => [\\\'--temp-dir=', $rsync_tempdir_prefix, $source, '\\\', ',
	   '                        \\\'--recursive\\\', \\\'--times\\\', ',
	   '                        \\\'--prune-empty-dirs\\\', ',
	   '                        \\\'--log-file-format=%i %b %n\\\', ',
	                    join (', ', map { '\\\'--compare-dest=' .  $_ . '/' . $path_in_destination . '/\\\'' }
	        		      ( @destination_roots )),
	   '                      , \\\'--log-file=', $rsync_log_prefix, $source, '\\\'] ',
	   '        }',
	   '    );\' ',
	   '};',
	   "\n",
##########  Get directory from source
	   '$rsync_dir_', $source, ' = File::Rsync->new; ',
##########  Return fodder for another eval
	   '$rsync_dir_exec_form{\'', $source, '\'} = sub {',
	   '    \'$rsync_dir_', $source, '->list(',
	   '        {',
	   '            src => \\\'', $source, $source_roots{$source}, '/\\\', ',
	   '            literal => [ \\\'--recursive\\\'] ',
	   '        }',
	   '    );\' ',
	   '}',
	   "\n"
	)};

sub act_on_keypress {
    my ($pressed_key) = @_;
    if ($pressed_key eq 267) { qx($key_f3_action) }
    elsif ($pressed_key eq 270) { qx($key_f6_action); }
}

# Run rsync for one $source, try all destinations
sub rsync_someplace {
    my ($source, @destinations) = @_;
    my $success = 0;
    foreach  (@destinations) {
	$destination_source_is_writing_to{$source} = $_;
	my $complete_destination = $_ . '/' . $path_in_destination;
	qx(mkdir -p $complete_destination/$rsync_tempdir_prefix$source);
	if (eval ($rsync_exec_form{$source} ($complete_destination))) {
	    debug_print "EVAL RSYNC_EXEC_FORM (successful) $source, $complete_destination: $@ \n";
	    $success = 1;
	    last; # unnecessary reruns would put empty dirs into otherwise unused destinations
	} else {
	    debug_print "EVAL RSYNC_EXEC_FORM (failed) $source, $complete_destination: $@ \n";
	    $success = 0;
	}
    }
    $success;
}


# Preparations done; sleeves up!

# Find usable destinations
@raw_mount_points = grep (s/\S+ on (.*) type .*/$1/, qx/mount/);
chomp @raw_mount_points;
@destination_roots = intersection @raw_mount_points, @usable_mount_points;
debug_print "DESTINATION_ROOTS:\n";
debug_print @destination_roots;

# Clean up destinations
map {
    my $p_i_d = $_ . '/' . $path_in_destination;
    my $p_i_d_backed_up =  $_ . '/' . $path_in_destination_backed_up;
    my $p_i_d_being_deleted =  $_ . '/' . $path_in_destination_being_deleted;
    if (-d $p_i_d_backed_up and -d $p_i_d_being_deleted) {
	warn "[" . $$ . "] Both $p_i_d_backed_up and $ p_i_d_being_deleted exist. This does not normally happen. I'm deleting $p_i_d_being_deleted. Be patient.\n";
	qx(rm -rf $p_i_d_being_deleted);
    }
    qx(mv -f $p_i_d_backed_up $p_i_d_being_deleted 2> /dev/null);
    $being_deleted_thread{$_} = async { qx(rm -rf $p_i_d_being_deleted); };
} @destination_roots;

# Set up and start things per source_root:
map {
    push (@destination_roots, shift (@destination_roots)); # rotate for crude load balancing
    $progress_ratios{$_} = " ?"; # Initialize (for UI)
    $rsync_worker_thread{$_} = async {
	while (1) {
	    my $rsync_log_name = $rsync_log_prefix . $_;
	    my $finished_name = $finished_prefix . $_;
	    debug_print 'rsync_preparation_form:' . rsync_preparation_form ($_). "\n";
	    eval rsync_preparation_form $_;
	    debug_print "EVAL RSYNC_PREPARATION_FORM $_: $@ \n";
	    debug_print 'rsync_dir_exec_form $_:'. $rsync_dir_exec_form{$_} () . "\n";
	    reassure_safe_file $finished_name;

	    if (rsync_someplace $_, @destination_roots) { 
		my @rsync_log = read_list $rsync_log_name;
		my @finished = safe_read $finished_name;
		my %filelist = map {$_, 42} @finished, grep (s/[\d\/\s:\[\]]+ [>c\.][fd]\S{9} \d+ (.*)/$1/,
							     @rsync_log);
		my @filelist = sort keys %filelist;
		safe_write $finished_name, @filelist;
		debug_print @filelist;
		my @source_dir = grep (s/[drwx-]+\s+\d+ [\d\/]+ [\d:]+ (.*)/$1/ , eval $rsync_dir_exec_form{$_} ());
		debug_print "EVAL RSYNC_DIR_EXEC_FORM $_: $@ \n";
		debug_print "SOURCE_DIR:\n";
		debug_print @source_dir;
		safe_write $finished_name, intersection @source_dir, @filelist;
		unlink $rsync_log_name unless $debug;
		debug_print "#######################################################################\n";
	    }
	    sleep $coffee_break;
	}
    }
} keys %source_roots;

# Provide some reassuring user information:
$destinations_monitor_thread = async {
    while () {
	map {
	    my $complete_destination = $_ . '/' . $path_in_destination;
	    qx(ls $complete_destination/* &> /dev/null);
	    $destination_usages{$_} = $? ? 0 : 1; # 0 = no new data
	    my @destination_usage_ratio = grep s/\S+\s+\S+\s+\S+\s+\S+\s+(\d*)%\s+\S+/$1/, qx(df $_);
	    chomp @destination_usage_ratio;
	    ($destination_usage_ratios{$_}) = @destination_usage_ratio;
	} @destination_roots;
	sleep $coffee_break;
    }
};

if ($debug) {
# Let the workers toil.
    sleep;
} else {
# Let the workers toil and talk to the user.
    initscr();
    cbreak();
    noecho();
    $window_left = newwin(17, 31, 0, 0);
    $window_right = newwin(17, 49, 0, 31);
    $window_center = newwin(5, 80, 17, 0);
    $window_bottom = newwin(3, 80, 22, 0);
    $window_bottom->keypad(1);
    $window_bottom->nodelay(1);
    start_color;
    init_pair 1, COLOR_GREEN, COLOR_BLACK;
    init_pair 2, COLOR_RED, COLOR_BLACK;
    init_pair 3, COLOR_BLUE, COLOR_BLACK;
    my $GREEN = COLOR_PAIR(1);
    my $RED   = COLOR_PAIR(2);
    my $BLUE  = COLOR_PAIR(3);
    
    while (1) {
	$window_left->box(0, 0);
	my $destinations_format = "%-15s%-11s%-3s";
	$window_left->addstr(1, 1,
			     sprintf($destinations_format,
				     "Removable", "Fresh", ""));
	$window_left->addstr(2, 1,
			     sprintf($destinations_format,
				     "Disk", "Data?", "%"));
	my $destination_usage;
	my $line_number = 4;
	map {
	    if ($destination_usages{$_}) {
		$window_left->attron($RED);
		$destination_usage = "yes";
	    } else {
		$window_left->attron($BLUE);
		$destination_usage = "no";
	    }
	    $window_left->addstr($line_number, 1,
				 sprintf($destinations_format, $_,
					 $destination_usage,
					 $destination_usage_ratios{$_}));
	    ++ $line_number;
	$window_left->attroff($RED);
	$window_left->attroff($BLUE);
	} @destination_roots;
	
	$window_right->box(0,0);
	my $sources_format = "%-15s%-10s%-6s%-15s";
	$window_right->addstr(1, 1,
			      sprintf ($sources_format,
				       "Data", "Speed", "To", "Writing"));
	$window_right->addstr(2, 1,
			      sprintf ($sources_format,
				       "Source", "", "Do", "To"));
	$line_number = 4;
	$window_right->attron($GREEN);
	map {
	    my $source = $_;
	    $window_right->addstr($line_number, 1,
				  sprintf($sources_format,
					  $source . $source_roots{$source},
					  $speeds{$source},
					  $progress_ratios{$source},
					  $destination_source_is_writing_to{$source}));
	    ++ $line_number;
	} sort (keys %source_roots);
	$window_right->attroff($GREEN);

	$line_number = 0;
#	$window_center->attron(A_BOLD);
	map {
	    $window_center->addstr($line_number, 3, $_);
	    ++ $line_number;
	} @monikop_ad;
#	$window_center->attroff(A_BOLD);

	$window_bottom->box(0,0);
	$window_bottom->attron(A_BOLD);
	$window_bottom->addstr(1, 10, "Turn off computer: [F3]              Restart computer: [F6]");
	$window_bottom->attroff(A_BOLD);

	$window_left->refresh();
	$window_right->refresh();
	$window_center->refresh();
	$window_bottom->refresh();
	act_on_keypress($window_bottom->getch());
	sleep 2;
    }
    endwin();
}


# Tidy up. (Except we don't reach this.)
map {
    $being_deleted_thread{$_}->join if $being_deleted_thread{$_};
} @destination_roots;

map {
    $rsync_worker_thread{$_}->join if $rsync_worker_thread{$_};
} @source_roots;


__END__
