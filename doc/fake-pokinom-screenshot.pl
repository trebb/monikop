#! /usr/bin/perl
#use strict;
#use warnings;
use File::Basename;
use File::Rsync;
use Thread 'async';
use threads::shared;
use Curses;

my @pokinom_banner = (
 "    _/_/_/      _/_/    _/    _/  _/_/_/  _/      _/    _/_/    _/      _/",
 "   _/    _/  _/    _/  _/  _/      _/    _/_/    _/  _/    _/  _/_/  _/_/ ", 
 "  _/_/_/    _/    _/  _/_/        _/    _/  _/  _/  _/    _/  _/  _/  _/  ", 
 " _/        _/    _/  _/  _/      _/    _/    _/_/  _/    _/  _/      _/   ", 
 "_/          _/_/    _/    _/  _/_/_/  _/      _/    _/_/    _/      _/    ",
    );
	
# Debug mode:
# 0 = clean UI; 1 = lots of scrolling junk; anything else = both (pipe to file)
my $debug = 0;


sub act_on_keypress {
    my ($pressed_key) = @_;
    if ($pressed_key eq 267) { qx($shut_down_action); }
    elsif ($pressed_key eq 273) { # F9
	$shut_down_when_done = $shut_down_when_done ? 0 : 1; }
}

my %being_deleted_thread;
my %rsync_worker_thread;
my $display_thread;

$ENV{USER} = $rsync_username if ($rsync_username);
$ENV{RSYNC_PASSWORD} = $rsync_password if ($rsync_password);

$SIG{TERM} = sub {
    $display_thread->kill('TERM')->join;
    die "Caught signal $_[0]";
};

# Preparations done; sleeves up!

# Make sure we have dirs to put our logs in:
## map {
##     my ($filename, $directory) = fileparse $_;
##     qx(mkdir -p $directory);
## } ( $rsync_log_prefix, $interrupted_prefix );
## 
## # Find usable (i.e. mounted) sources
## my @raw_mount_points = grep (s/\S+ on (.*) type .*/$1/, qx/mount/);
## chomp @raw_mount_points;
## my @sources = intersection @raw_mount_points, @usable_mount_points;
## debug_print "SOURCES:\n";
## debug_print @sources;
@sources = (
    '/media/disk_1',
    '/media/disk_2',
    '/media/disk_3',
    '/media/disk_4',
    '/media/disk_5',
    '/media/disk_6',
    '/media/disk_7',
    );

# Turn a path into a legal perl identifier:
sub make_key_from_path {
    my $path = shift;
    ($path) =~ s/\/?(.*)\/?/$1/g;
    ($path) =~ s/\W/_/g;
    $path;
}

map {
    $source_roots{make_key_from_path $_} = $_
} @sources;

%speeds = (
    'media_disk_1' => '15.20MB/s',
    'media_disk_2' => '10.02MB/',
    'media_disk_3' => '-',
    'media_disk_4' => '242.73kB/s',
    'media_disk_5' => '6.78MB/s',
    'media_disk_6' => '-',
    'media_disk_7' => '-',
    );

%done = (
    'media_disk_1' => 0,
    'media_disk_2' => 0,
    'media_disk_3' => 1,
    'media_disk_4' => 0,
    'media_disk_5' => 0,
    'media_disk_6' => 0,
    'media_disk_7' => 1,
    );

%progress_ratios = (
    'media_disk_1' => '951/2300', 
    'media_disk_2' => '217/352',  
    'media_disk_3' => 'Done',        
    'media_disk_4' => '16/223',   
    'media_disk_5' => '1854/1929',
    'media_disk_6' => 'Wait',
    'media_disk_7' => 'Done',
    );


unless ($debug == 1) {
# Talk to the user.
    $display_thread = async {
        $SIG{TERM} = sub {
            endwin();           # Leave a usable terminal.
            threads->exit()
        };

        my $redraw_window_count = 0;
        initscr();
        cbreak();
        noecho();
        curs_set(0);
        my $window_top = newwin(24 - 8, 79, 0, 0);
        my $window_center = newwin(5, 79, 24 - 8, 0);
        my $window_bottom = newwin(3, 79, 24 - 3, 0);
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
            my $line_number = 2;
            map {
                my $source = $_;
                $window_top->attron($CYAN);
                $window_top->attron($RED) if $done{$source};
                $window_top->
                    addstr($line_number, 12,
                           sprintf($sources_format,
                                   substr($source_roots{$source}, 0, 24),
                                   substr($speeds{$source}, 0, 17),
                                   substr($progress_ratios{$source}, -8, 8)));
                ++ $line_number;
                $window_top->addstr($line_number, 1,
                                    sprintf($sources_format, "", "", "", ""));
                $window_top->attroff($RED);
                $window_top->attroff($CYAN);
            } sort (keys %source_roots);
            $line_number = 0;
            map {
                $window_center->addstr($line_number, 2, $_);
                ++ $line_number;
            } @pokinom_banner;
            $window_center->move(0, 0);

            $window_bottom->box(0,0);
            $window_bottom->attron(A_BOLD);
            $window_bottom->
                addstr(1, 3,
                       sprintf ("[F3]: Turn off now.%54s",
                                $shut_down_when_done ? "Turning off when done.  [F9]: Stay on."
                                : "Staying on.  [F9]: Turn off when done."));
            $window_bottom->attroff(A_BOLD);

            $window_top->noutrefresh();
            $window_bottom->noutrefresh();
            $window_center->noutrefresh(); # Last window gets the cursor.
            sleep 2;
            if (++ $redraw_window_count > 5) {
                $redraw_window_count = 0;
                redrawwin();
            }
            doupdate();
            act_on_keypress($window_bottom->getch());
            if (! grep(/0/, values %done) && $shut_down_when_done) {
                qx ($shut_down_action);
            }
        }
        endwin();
    };
}

sleep;

