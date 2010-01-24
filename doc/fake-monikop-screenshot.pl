#! /usr/bin/perl
#use strict;
#use warnings;
use integer;
use File::Rsync;
use File::Basename;
use Thread 'async';
use threads::shared;
use Curses;

my @monikop_banner = (
  "    _/      _/    _/_/    _/      _/  _/_/_/  _/    _/    _/_/    _/_/_/ ", 
  "   _/_/  _/_/  _/    _/  _/_/    _/    _/    _/  _/    _/    _/  _/    _/",
  "  _/  _/  _/  _/    _/  _/  _/  _/    _/    _/_/      _/    _/  _/_/_/   ", 
  " _/      _/  _/    _/  _/    _/_/    _/    _/  _/    _/    _/  _/        ", 
  "_/      _/    _/_/    _/      _/  _/_/_/  _/    _/    _/_/    _/         ",
  );
	
# Debug mode:
# 0 = clean UI; 1 = lots of scrolling junk; anything else = both (pipe to file)
my $debug = 0;
$debug = $ARGV[1] if $ARGV[1];

# Where to read local configuration:
my $monikop_config = '~/monikop/monikop.config';
$monikop_config = $ARGV[0] if $ARGV[0];

########################################
# Settings
########################################
# Possible data sources, and by what directory name to represent them in
# destination.
# When the latter is not unique, care must be taken that all pathnames in the 
# respective sources are unique.
my %sources = (
    'data_producer1::data' => 'p1_dir',
    'data_producer2::data' => 'p2_dir',
    'data_producer3::data' => '',
    'data_producer4::data' => '',
    );

# Places to store run-time information to share between threads:
my %speeds :shared; # rsync output
my %progress_ratios :shared; # rsync output
my %destination_usages :shared; # i.e. used/unused
my %destination_usage_ratios :shared;
my %destination_source_is_writing_to :shared;
my %reachable :shared;

sub debug_print { if ($debug) { print @_; } };

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

sub act_on_keypress {
    my ($pressed_key) = @_;
    if ($pressed_key eq 267) { qx($key_f3_action) }
    elsif ($pressed_key eq 270) { qx($key_f6_action); }
}

%destination_source_is_writing_to = (
    make_key_from_path ('/data_producer1::data') => '/media/disk_2',
    make_key_from_path ('/data_producer2::data') => '/media/disk_1',
    make_key_from_path ('/data_producer3::data') => '/media/disk_3',
    );

$SIG{TERM} = sub {
    $display_thread->kill('TERM')->join;
    die "Caught signal $_[0]";
};

@destination_roots = (
    '/media/disk_1',
    '/media/disk_2',
    '/media/disk_3',
    '/media/disk_7',
    );

%destination_usage_ratios = (
    '/media/disk_1' => 38,
    '/media/disk_2' => 94,
    '/media/disk_3' => 10,
    '/media/disk_7' => 6,
    );
    
%destination_usages = (
    '/media/disk_1' => 1,
    '/media/disk_2' => 1,
    '/media/disk_3' => 1,
    '/media/disk_7' => 0,
    );

%reachable = (
    'data_producer1__data' => 1,
    'data_producer2__data' => 1,
    'data_producer3__data' => 1,
    );

%speeds = (
    'data_producer1__data' => '23.30MB/s',
    'data_producer2__data' => '23.30MB/s',
    'data_producer3__data' => '23.30MB/s',
    );

%progress_ratios = (
    'data_producer1__data' => '951/2300',
    'data_producer2__data' => '951/2300',
    'data_producer3__data' => '951/2300',
    );

unless ($debug == 1) {
# Talk to the user.
    $display_thread = async {
        $SIG{TERM} = sub {
            endwin(); # Leave a usable terminal.
            threads->exit()
        };

        my $redraw_window_count = 0;
        initscr();
        cbreak();
        noecho();
        curs_set(0);
        my $window_left = newwin(LINES() -8, 29, 0, 0);
        my $window_right = newwin(LINES() -8, 50, 0, 29);
        my $window_center = newwin(5, 79, LINES() -8, 0);
        my $window_bottom = newwin(3, 79, LINES() -3, 0);
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
            $window_left->addstr(1, 1, sprintf($destinations_format,
					       "Removable", "Fresh", "Usg"));
            $window_left->addstr(2, 1, sprintf($destinations_format,
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
                $window_left->
		    addstr($line_number, 1,
			   sprintf($destinations_format,
				   substr($_, -17, 17),
				   substr($destination_usage, -6, 6),
				   substr($destination_usage_ratios{$_}
					  ? $destination_usage_ratios{$_}
					  : "?",
					  -3, 3)));
                ++ $line_number;
                $window_left->attroff($RED);
                $window_left->attroff($CYAN);
            } sort @destination_roots;

            $window_right->attron($MAGENTA);
            $window_right->box(0,0);
            $window_right->addstr(0, 19, "Data Sources");
            $window_right->attroff($MAGENTA);
            my $sources_format = "%-15s%-11s%-9s%-13s";
            $window_right->attron(A_BOLD);
            $window_right->
		addstr(1, 1, sprintf ($sources_format,
				      "Data", "", "Files", " Writing"));
            $window_right->
		addstr(2, 1, sprintf ($sources_format,
				      "Source", "Speed", "To Copy", " To"));
            $window_right->attroff(A_BOLD);
            $line_number = 3;
            $window_right->attron($MAGENTA);
            map {
                my $source = $_;
                my $current_destination = '?';
                if (exists $destination_source_is_writing_to{$source}) {
                    $current_destination =
                        $destination_source_is_writing_to{$source};
                }
                if ($reachable{$source}) { 
                    $window_right->
			addstr($line_number, 1,
			       sprintf($sources_format,
				       substr($source_roots{$source}, 0, 14),
				       substr($speeds{$source}, 0, 11),
				       substr($progress_ratios{$source},
					      -9, 9),
				       substr($current_destination, -13, 13)));
                    ++ $line_number;
                }
                $window_right->
		    addstr($line_number, 1,
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
            $window_bottom->addstr(1, 3, "[F3]: Turn off computer.");
            $window_bottom->addstr(1, 53, "[F6]: Restart computer.");
            $window_bottom->attroff(A_BOLD);

            $window_left->noutrefresh();
            $window_right->noutrefresh();
            $window_bottom->noutrefresh();
            $window_center->noutrefresh(); # Last window gets the cursor.
            act_on_keypress($window_bottom->getch());
            sleep 2;
            if (++ $redraw_window_count > 5) {
                $redraw_window_count = 0;
                redrawwin();
            }
            doupdate();
        }
    endwin();
    };
}

sleep;
