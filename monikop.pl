#! /usr/bin/perl
#use strict;
use warnings;
#use diagnostics;
use integer;
use Data::Dumper;
use File::Rsync;
use Thread 'async';
use threads::shared;
use Curses;

my @monikop_banner = (
    "    _/      _/    _/_/    _/      _/  _/_/_/  _/    _/    _/_/    _/_/_/ ", 
    "   _/_/  _/_/  _/    _/  _/_/    _/    _/    _/  _/    _/    _/  _/    _/",
    "  _/  _/  _/  _/    _/  _/  _/  _/    _/    _/_/      _/    _/  _/_/_/   ", 
    " _/      _/  _/    _/  _/    _/_/    _/    _/  _/    _/    _/  _/        ", 
    "_/      _/    _/_/    _/      _/  _/_/_/  _/    _/    _/_/    _/         "
    );
	
########################################
# Global defaults
########################################
# Possible data sources, and by what directory name to represent them in
# destination.
# When the latter is not unique, care must be taken that all pathnames in the 
# respective sources are unique.
%sources = (
#    'tt9/log' => '9',
#    'tt10/log' => '10',
    'tt11/log' => '11',
#    'vvastr164::ftp' => '164',
    'vvastr164::ftp1' => '164-1',
    'lsstr174::rsynctest' => '174',
    );

# Possible mount points of data destinations. Must be unique.
@usable_mount_points = (
#    '/root/tt6',
    '/root/tt7',
    '/root/tt8',
    '/blah',
    );

# Common directory (under a mount point) to put new data in:
$path_in_destination =
    'measuring_data'
    ;

# Directories (under any mount point) of this name will be deleted:
$path_in_destination_backed_up =
    'backed_up'
    ;

# Directory name (under a mount point) while being deleted:
$path_in_destination_being_deleted =
    'being_deleted'
    ;

# Path and file name prefix of rsync's raw logs:
$rsync_log_prefix =
    '/root/log.'
    ;

# Path and file name prefix of the list of successfully rsynced files:
$finished_prefix =
    '/root/finished.'
    ; 

# How to suffix the name of the duplicate of a safe file:
$safe_file_backup_suffix =
    '.bak'
    ; 

# How to suffix the name of an unfinished safe file:
$safe_file_unfinished_suffix =
    '.unfinished'
    ; 

# What to do (shutdown) when F3 has been pressed:
$key_f3_action =
    "touch f3_pressed"
    ;

# What to do (reboot) when F6 has been pressed:
$key_f6_action =
    "touch f6_pressed"
    ;

# Rsyncs time (in seconds) to wait for a response:
my $rsync_timeout =
    30
    ;

# Rsyncs directory (relative to destination) for partially transferred files:
my $rsync_partial_dir_name =
    '.rsync_partial'
    ;

# Local changes to the above.
### do "monikop.config";

# 0 = clean UI; 1 = lots of scrolling junk; anything else = both (pipe to file)
my $debug = 0; 

# Time in seconds before rsync is restarted and user information is recalculated:
$coffee_break = 10;

# Places to store run-time information to share between threads:
my %speeds :shared; # rsync output
my %progress_ratios :shared; # rsync output
my %destination_usages :shared; # i.e. used/unused
my %destination_usage_ratios :shared;
my %destination_source_is_writing_to :shared;
my %reachable :shared;

sub debug_print { if ($debug) { print @_; } };

# Return the hash referenced by argument, which is sorted if accessed as an array:
sub sort_hash {
    %hash_table = @_;
    my @sorted_hash = ();
    foreach my $key (sort keys %hash_table) {
	push @sorted_hash, $key, $hash_table{$key};
    }
    @sorted_hash;
}

# Turn a path into a legal perl identifier:
sub make_key_from_path {
    my $path = shift;
    ($path) =~ s/\/?(.*)\/?/$1/g;
    ($path) =~ s/\W/_/g;
    $path;
}

my %source_roots;
map {
    $source_roots{make_key_from_path $_} = $_
} keys %sources;

my %source_dirs_in_destination;
map {
    $source_dirs_in_destination{make_key_from_path $_} = $sources{$_}
} keys %sources;

# Crudely turn date string(s) into a number. Chronological order is preserved.
sub normalize_date {
    my $date = join '', @_;
    $date =~  tr/ \/:-//d;
    $date;
}

# Return sorted intersection of arrays which are supposed to have unique
# elements:
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

# Write @content to a file with name $filename or a name starting with $filename
# and ending with $safe_file_backup_suffix. Leave at least one such file, even
# if interrupted.
sub safe_write {
    my ($filename, @content) = @_;
    my $filename_a = $filename;
    my $filename_b = $filename . $safe_file_backup_suffix;
    my $filename_unfinished = $filename . $safe_file_unfinished_suffix;
    local (*FILE_UNFINISHED);
    open FILE_UNFINISHED, '>', $filename_unfinished
	or die "[" . $$ . "] open $filename_unfinished failed: $!\n";
    print FILE_UNFINISHED @content;
    close FILE_UNFINISHED;
    qx(cp $filename_unfinished $filename_b);
    qx(mv $filename_unfinished $filename_a);
}

# Put contents of $filename into an array:
sub read_list {
    my ($filename) = @_;
    local (*FILE);
    open FILE, '<', $filename or warn "[" . $$ . "] open $filename failed: $!\n";
    my @value = <FILE>;
    close FILE;
    @value;
}

# Read a file written by safe_write
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
    $speeds{$source} = "-";
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
	   '        $speeds{\'', $source, '\'} = "-";',
	   '    };',
	   '    if ($progress_ratio and $outputchannel eq \'out\') {',
	   '        $progress_ratios{\'', $source, '\'} = $progress_ratio;',
	   '    } ;',
	   '};',
	   "\n",
##########  Run rsync: main worker
	   '$rsync_', $source, ' = File::Rsync->new; ',
##########  Return fodder for another eval
	   '$rsync_exec_form{\'', $source, '\'} = sub {',
	   '    my ($complete_destination) = @_;',
	   '    \'$rsync_', $source, '->exec(',
	   '        {',
	   '            src => \\\'', $source_roots{$source}, '/\\\', ',
	   '            dest => \\\'\' . $complete_destination . \'/\\\', ',
	   '            outfun => $rsync_outfun_', $source, ', ', 
	   '            progress => 1, debug => 0, verbose => 0, ',
	   '    	filter => [\\\'merge,- ', $finished_prefix, $source, '\\\'], ',
	   '            literal => [',
	   '                        \\\'--recursive\\\', \\\'--times\\\', ',
	   '                        \\\'--partial-dir=', $rsync_partial_dir_name, '\\\', ',
	   '                        \\\'--timeout=', $rsync_timeout, '\\\', ',
	   '                        \\\'--prune-empty-dirs\\\', ',
	   '                        \\\'--log-file-format=%i %b %l %M %n\\\', ',
	                    join (', ', map { '\\\'--compare-dest=' .  $_ . '/'
						  . $path_in_destination . '/'
						  . $source_dirs_in_destination{$source} . '/\\\'' }
				  ( @destination_roots )),
	   '                      , \\\'--log-file=', $rsync_log_prefix, $source, '\\\'] ',
	   '        }',
	   '    );\' ',
	   '};',
	   "\n",
##########  Run rsync: get directory from source
	   '$rsync_dir_', $source, ' = File::Rsync->new; ',
##########  Return fodder for another eval: dir
	   '$rsync_dir_exec_form{\'', $source, '\'} = sub {',
	   '    \'$rsync_dir_', $source, '->list(',
	   '        {',
	   '            src => \\\'', $source_roots{$source}, '/\\\', ',
	   '            literal => [ \\\'--recursive\\\', ',
	   '                         \\\'--timeout=', $rsync_timeout, '\\\'] ',
	   '        }',
	   '    );\' ',
	   '};',
	   "\n",
##########  Return fodder for another eval: error code from last rsync call
	   '$rsync_dir_err_form{\'', $source, '\'} = sub {',
	   '    \'$rsync_dir_', $source, '->err();\' ',
	   '}',
	   "\n"
	)};

sub act_on_keypress {
    my ($pressed_key) = @_;
    if ($pressed_key eq 267) { qx($key_f3_action) }
    elsif ($pressed_key eq 270) { qx($key_f6_action); }
}

# Run rsync for one $source, try all destinations:
sub rsync_someplace {
    my ($source, @destinations) = @_;
    my $success;

    my $rsync_log_name = $rsync_log_prefix . $source;
    my $finished_name = $finished_prefix . $source;
    foreach (@destinations) {
	$destination_source_is_writing_to{$source} = $_;
	my $common_destination = $_ . '/' . $path_in_destination;
	my $complete_destination = $common_destination . '/'
	    . $source_dirs_in_destination{$source};
	qx(mkdir -p $common_destination);
	if ($?) { die "Fatal: $common_destination is not writable."}
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

# Find usable destinations:
@raw_mount_points = grep (s/\S+ on (.*) type .*/$1/, qx/mount/);
chomp @raw_mount_points;
@destination_roots = intersection @raw_mount_points, @usable_mount_points;
debug_print "DESTINATION_ROOTS:\n";
debug_print @destination_roots;

# Clean up destinations:
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
    # rotate for crude load balancing:
    push (@destination_roots, shift (@destination_roots)); 
    $progress_ratios{$_} = "?"; # Initialize for UI
    $rsync_worker_thread{$_} = async {
	while (1) {
	    my $rsync_log_name = $rsync_log_prefix . $_;
	    my $finished_name = $finished_prefix . $_;
	    debug_print 'rsync_preparation_form:' . rsync_preparation_form ($_). "\n";
	    eval rsync_preparation_form $_;
	    debug_print "EVAL RSYNC_PREPARATION_FORM $_: $@ \n";
	    debug_print 'rsync_dir_exec_form $_:'. $rsync_dir_exec_form{$_} () . "\n";
	    my @rsync_ls = eval $rsync_dir_exec_form{$_}();
	    eval $rsync_dir_err_form{$_}();
	    $reachable{$_} = eval $rsync_dir_err_form{$_}() ? 0 : 1;
	    debug_print "REACHABLE: $reachable{$_}\n";
	    if ($reachable{$_}) {
		my %old_finished = safe_read $finished_name;
		if (-f $rsync_log_name) { 
		    my @rsync_log = read_list $rsync_log_name;
		    foreach (@rsync_log) {
			my ($file_length, $modification_time, $filename) =
			    /[\d\/\s:\[\]]+ [>c\.][fd]\S{9} \d+ (\d+) ([\d\/:-]+) (.*)$/;
			if ($filename) {
			    $old_finished{$filename . "\n"} =
				"### " . $modification_time . " " . $file_length . "\n";
			}
		    }
		    safe_write $finished_name, sort_hash %old_finished;
		    unlink $rsync_log_name unless $debug;
		}
		my %finished = ();
		# Delete from %old_finished what has to be re-rsynced.
		foreach (@rsync_ls) {
		    my ($ls_size, $ls_modification_date,
			$ls_modification_time, $ls_filename) =
			    /[drwx-]+\s+(\d+) ([\d\/]+) ([\d:]+) (.*)/;
		    if ($ls_filename && exists $old_finished{$ls_filename . "\n"}) {
			my ($finished_modification_date, $finished_size) =
			    $old_finished{$ls_filename . "\n"} =~ /### (\S+) (\d+)$/;
			if ( ($finished_size eq $ls_size)
			     && (normalize_date ($finished_modification_date)
				 eq normalize_date ($ls_modification_date,
						    $ls_modification_time)) )
			{
			    $finished{$ls_filename . "\n"} =
				$old_finished{$ls_filename . "\n"};
			}
		    }
		}
		safe_write $finished_name, %finished;
		if (rsync_someplace $_, @destination_roots) {
		    $progress_ratios{$_} = '0'; # Clean staleness for UI
		}
		sleep $coffee_break;
	    }
	}
    }
} keys %source_roots;

# Provide some reassuring user information:
my $destinations_monitor_thread = async {
    while () {
	map {
	    my $destination_root = $_;
	    my $destination_usage = 0;
	    map {
		my $source_root = $_;
		my $complete_destination = $destination_root . '/'
		    . $path_in_destination . '/'
		    . $source_dirs_in_destination{$source_root};
		my @dir = qx(ls -A $complete_destination/ 2> /dev/null);
		$destination_usage = 1 if scalar @dir; # 0 = no new data
	    } keys %source_roots;
	    $destination_usages{$destination_root} = $destination_usage;
	    my @destination_usage_ratio =
		grep s/\S+\s+\S+\s+\S+\s+\S+\s+(\d*)%\s+\S+/$1/, qx(df $_);
	    chomp @destination_usage_ratio;
	    ($destination_usage_ratios{$_}) = @destination_usage_ratio;
	} @destination_roots;
	sleep $coffee_break;
    }
};

if ($debug == 1) {
# Let the workers toil.
    sleep;
} else {
# Let the workers toil; talk to the user.
    initscr();
    cbreak();
    noecho();
    curs_set(0);
    my $window_left = newwin(LINES() -8, 29, 0, 0);
    my $window_right = newwin(LINES() - 8, 50, 0, 29);
    my $window_center = newwin(5, 79, LINES() - 8, 0);
    my $window_bottom = newwin(3, 79, LINES() - 3, 0);
    $window_bottom->keypad(1);
    $window_bottom->nodelay(1);
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
	$window_left->attron($CYAN);
	$window_left->box(0, 0);
	$window_left->addstr(0, 6, "Data Destinations");
	$window_left->attroff($CYAN);
	my $destinations_format = "%-18s%-6s%-3s";
	$window_left->attron(A_BOLD);
	$window_left->addstr(1, 1,
			     sprintf($destinations_format,
				     "Removable", "Fresh", "Usg"));
	$window_left->addstr(2, 1,
			     sprintf($destinations_format,
				     "Disk", "Data?", "%"));
	$window_left->attroff(A_BOLD);
	my $destination_usage;
	my $line_number = 3;
	map {
	    if ($destination_usages{$_}) {
		$window_left->attron($RED);
		$destination_usage = "yes";
	    } else {
		$window_left->attron($CYAN);
		$destination_usage = "no";
	    }
	    $window_left->addstr($line_number, 1,
				 sprintf($destinations_format,
					 substr($_, -17, 17),
					 substr($destination_usage, -6, 6),
					 substr($destination_usage_ratios{$_}, -3, 3)));
	    ++ $line_number;
	$window_left->attroff($RED);
	$window_left->attroff($CYAN);
	} sort @destination_roots;
	
	$window_right->attron($MAGENTA);
	$window_right->box(0,0);
	$window_right->addstr(0, 19, "Data Sources");
	$window_right->attroff($MAGENTA);
	my $sources_format = "%-18s%-11s%-6s%-13s";
	$window_right->attron(A_BOLD);
	$window_right->addstr(1, 1,
			      sprintf ($sources_format,
				       "Data", "", "To", "Writing"));
	$window_right->addstr(2, 1,
			      sprintf ($sources_format,
				       "Source", "Speed", "Do", "To"));
	$window_right->attroff(A_BOLD);
	$line_number = 3;
	$window_right->attron($MAGENTA);
	map {
	    my $source = $_;
	    my $current_destination = '?';
	    if (exists $destination_source_is_writing_to{$source}) {
		$current_destination = $destination_source_is_writing_to{$source};
	    }
	    if ($reachable{$source}) { 
		$window_right->addstr($line_number, 1,
				      sprintf($sources_format,
					      substr($source_roots{$source}, 0, 17),
					      substr($speeds{$source}, 0, 11),
					      substr($progress_ratios{$source}, -6, 6),
					      substr($current_destination, -13, 13)));
		++ $line_number;
	    }
	    $window_right->addstr($line_number, 1,
				  sprintf($sources_format, "", "", "", ""));
	} sort (keys %source_roots);
	$window_right->attroff($MAGENTA);

	$line_number = 0;
	map {
	    $window_center->addstr($line_number, 2, $_);
	    ++ $line_number;
	} @monikop_banner;
	$window_center->move(0, 0);

	$window_bottom->box(0,0);
	$window_bottom->attron(A_BOLD);
	$window_bottom->addstr(1, 3, "[F3]: Turn off computer.                         [F6]: Restart computer.");
	$window_bottom->attroff(A_BOLD);

	$window_left->refresh();
	$window_right->refresh();
	$window_bottom->refresh();
	$window_center->refresh(); # Last window gets the cursor.
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
} keys %source_roots;

$destinations_monitor_thread->join if $destinatios_monitor_thread;

__END__
