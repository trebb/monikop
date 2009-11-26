#! /usr/bin/perl
#use strict;
use warnings;
#use diagnostics;
use Data::Dumper;
#use List::Util qw/max min sum/;
#use Proc::ProcessTable;
#use Proc::Killfam;
use Net::Ping;
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

#$pinger = Net::Ping->new('tcp', 1);
##### Einstellungen vom Inifile lesen
#$inifile_name = ($0 . ".ini");
#$ini = XMLin($inifile_name, SuppressEmpty => 1, forcearray => [ 'MOUNTPOINTS' ]);
#$hddmem_factor = $ini->{INI}{HDDMEM_FACTOR}; #### Das soviel-fache an Platz muss vorhanden sein
##### Mögliche Ziellaufwerke (ohne abschließenden "/"):
#@mountpoints = @{$ini->{INI}{MOUNTPOINTS}};
#$dest_dir = $ini->{INI}{DEST_DIR};
#$statusfile_name = $ini->{INI}{STATUSFILE_NAME};
#$lockfile_name = $ini->{INI}{LOCKFILE_NAME};
#$backed_up_file_name = $ini->{INI}{BACKED_UP_FILE_NAME};
##### Place file $copy_postponed_file_name containing a single '*' in any source dir which is not to
##### be copied.
#$copy_postponed_file_name = $ini->{INI}{COPY_POSTPONED_FILE_NAME}; # another rsync filter
#$rsync_filter_prefix = $ini->{INI}{RSYNC_FILTER_PREFIX};

#$src_root = 'tt11/';

#$src_root = @ARGV[0];
## Don't mess up status file if $src_root is unreachable:
#($host, $module) = split ':', $src_root;
#unless ($pinger->ping($host)) {
#    die "$host unreachable";
#}
#$der_name = 'R_' . uc ($src_root); # in XML sind Zahlen als Namensanfang verboten.
#$der_name =~ s|[/:.]|_|g;
#$rsync_filter_name = $rsync_filter_prefix . $der_name . '.txt';
#$rsync_log_name = $der_name . '.log';
#$progressfile_name = $der_name . '.progress';
#$speedfile_name = $der_name . '.speed';
#$statusfile_name_bak = $statusfile_name . ".bak";
#$status = getstatus_lock;
#${$status}{$der_name}{'STATUS'} = 'JUST_STARTED';
#${$status}{$der_name}{'TIME_OF_STATUS'} = time;
#${$status}{$der_name}{'SOURCE'} = $src_root;
#${$status}{$der_name}{'PROGRESSFILE'} = $progressfile_name;
#${$status}{$der_name}{'SPEEDFILE'} = $speedfile_name;
#putstatus_unlock $status;
##### Hieraus können andere Progs eine Fortschrittsanzeige machen:
#open PROGRESSFILE, '>>', $progressfile_name or die "[" . $$ . "] open $progressfile_name failed: $!\n";
##### Hieraus können andere Progs eine Geschwindigkeitsanzeige machen:
#open SPEEDFILE, '>>', $speedfile_name or die "[" . $$ . "] open $speedfile_name failed: $!\n";


#$proctab = new Proc::ProcessTable;
#foreach $process ( @{$proctab->table} ) {
#    if ($process->pid == $$) {
#	$cmndline = canonical_cmndline ($process->cmndline);
#	print "[" . $$ . "] Das bin ich: ". $cmndline . "\t" . $process->pid . "\n" if $debug;
#	foreach $process_2 ( @{$proctab->table} ) {
#	    if (canonical_cmndline ($process_2->cmndline) eq $cmndline
#		&& not $process_2->pid == $$ ) {
#		$status = getstatus_lock;
#		${$status}{$der_name}{'STATUS'} = 'KILL_BROTHER';
#		${$status}{$der_name}{'TIME_OF_STATUS'} = time;
#		putstatus_unlock $status;
#		warn $0 . ": Etwas wie ich [" . $$ . "] läuft schon: " . 
#		    $process_2->cmndline . $process_2->pid . " (wird gekillt)\n";
#		killfam ('TERM', $process_2->pid);
#	    }
#	}
#	last;
#    }
#}
#$time0 = time;

########################################
# Global defaults
########################################
@usable_mount_points = ('/root/tt6', '/root/tt7', '/root/tt8', '/blah'); # Possible mount points. Must be unique.
$path_in_destination = 'measuring_data';
$path_in_destination_backed_up = 'backed_up';
$path_in_destination_being_deleted = 'being_deleted';
$rsync_tempdir_prefix = '.rsync_temp_';
# Possible sources.
%source_roots = ('tt11' => '/log', 'tt10' => '/log', 'tt9' => '/log', 'vvastr164' => '::ftp');
#%source_roots = ('tt11' => '/log');
$rsync_log_prefix = '/root/log.'; # rsync's raw log; prepend path.
$finished_prefix = '/root/finished_'; # List of successfully rsynced files; prepend path.
$progressfile_prefix = '/root/progress_'; # UI data; prepend path.
$speedfile_prefix = '/root/speed_'; # UI data; prepend path.
$safe_file_backup_suffix = '_bak'; # How to name the duplicate of a safe file.
$safe_file_unfinished_suffix = '_unfinished'; # Name of a safe file wannabe.
$debug = 2;

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
    print "SAFE_READ: $filename";
    read_list $filename;
}

sub rsync_preparation_form {
    my ($source) = @_;
    join ( '',
	   "\n",
##########  Write rsync's status messages for reading by a GUI
	   '$rsync_outfun_', $source, ' = sub ',
	   '{',
	   '    ($outline, $outputchannel) = @_ ; ',
	   '    ($progressratio) = $outline =~ /.+to-check=(\d+\/\d+)\)$/; ',
	   '    ($speed) = $outline =~ /\d+\s+\d+%\s+(\S+)/; ',
	        # no print but unbuffered writing:
	   '    if ($speed and $outputchannel eq \'out\')',
	   '    {',
	   '        sysseek SPEEDFILE_', $source,', 0, SEEK_SET; ',
	   '        syswrite SPEEDFILE_', $source,
	   '            , $speed . "\n          "; ',
	   '    };',
	   '    if ($progressratio and $outputchannel eq \'out\')',
	   '    {',
	   '        sysseek PROGRESSFILE_', $source,', 0, SEEK_SET; ',
	   '        syswrite PROGRESSFILE_', $source,
	   '            , $progressratio . "\n          "; ',
	   '    };',
	   '};',
	   "\n",
	   'open PROGRESSFILE_', $source, ', \'>\', \'', $progressfile_prefix, $source, '\'',
	   '    or die "[" . $$ . "] open ', $progressfile_prefix, $source, ' failed: $!\n";',
	   "\n",
	   'open SPEEDFILE_', $source, ', \'>\', \'', $speedfile_prefix, $source, '\'',
	   '    or die "[" . $$ . "] open ', $speedfile_prefix, $source, ' failed: $!\n";',
	   "\n",
##########  Run rsync
	   '$rsync_', $source, ' = File::Rsync->new; ',
##########  Return fodder for another eval
	   '$rsync_exec_form{\'', $source, '\'} = sub ',
	   '{ ',
	   '    my ($complete_destination) = @_; print "COMPLETE_DESTINATION(rsync_exec_form): $complete_destination \n";',
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
	   '$rsync_dir_exec_form{\'', $source, '\'} = sub ',
	   '{ ',
	   '    \'$rsync_dir_', $source, '->list(',
	   '        {',
	   '            src => \\\'', $source, $source_roots{$source}, '/\\\', ',
	   '            literal => [ \\\'--recursive\\\'] ',
	   '        }',
	   '    );\' ',
	   '}',
	   "\n"
	)};

# Run rsync for one $source, try all destinations
# TODO: Put this in its own thread.
sub rsync_someplace
{
    my ($source, @destinations) = @_;
    map
    {
	my $complete_destination = $_ . '/' . $path_in_destination;
	debug_print "######################################\n";
	print "COMPLETE_DESTINATION:$complete_destination \n";
	debug_print "RSYNC_EXEC_FORM $source, $_:" . $rsync_exec_form{$source} ($complete_destination) . "\n";
	debug_print "######################################\n";
	qx(mkdir -p $complete_destination/$rsync_tempdir_prefix$source);
	eval ($rsync_exec_form{$source} ($complete_destination));
	debug_print "EVAL RSYNC_EXEC_FORM $source, $complete_destination: $@ \n";
    } @destinations;
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
    my $rsync_log_name = $rsync_log_prefix . $_;
    my $finished_name = $finished_prefix . $_;
    debug_print 'rsync_preparation_form:' . rsync_preparation_form ($_). "\n";
    eval rsync_preparation_form $_;
    debug_print "EVAL RSYNC_PREPARATION_FORM $_: $@ \n";
    debug_print 'rsync_dir_exec_form $_:'. $rsync_dir_exec_form{$_} () . "\n";
    reassure_safe_file $finished_name;
    rsync_someplace $_, @destination_roots; # TODO: rotate @destination_roots for load balancing: push (shift ...)...
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

    @intersection = intersection @source_dir, @filelist;

    debug_print "INTERSECTION:\n";
    debug_print @intersection;
    safe_write $finished_name, @intersection;
    unlink $rsync_log_name unless $debug;
    debug_print "#######################################################################\n";
} keys %source_roots;

# Tidy up
map {
    $being_deleted_thread{$_}->join if $being_deleted_thread{$_};
} @destination_roots;
__END__



    #### Filterdateien von Quelle holen:
    $status = getstatus_lock;
    ${$status}{$der_name}{'STATUS'} = "RECEIVE_FILTERFILES";
    ${$status}{$der_name}{'TIME_OF_STATUS'} = time;
    putstatus_unlock $status;
    $rsync->exec( { src => $src_root, dest => $dest_root, 
		    filter => ['include */', 'include ' . $rsync_filter_name, 'exclude *',
			       'dir-merge,- ' . $copy_postponed_file_name] } )
	or die "[" . $$ . "] rsync (4) failed: " . $rsync->lastcmd . " $!\n";
    print "[" . $$ . "]{" . (time - $time0) . "} Filterdaten geholt\n" if $debug;
    foreach (@dateiliste) {
	/\S+\s\S+\s\[\S+\]\s[><ch\.]f\S+\s[0-9]+\s(.+)/g;
	@tmp = splitpath($1);
	push ( @{$dirs {$tmp[1]}}, $tmp[2] ); # Dirname = Key in $dirs, Referenz auf Filename-Array = Wert
    }
    print "[" . $$ . "]{" . (time - $time0) . "} Dateiliste ausgewertet\n" if $debug;
    #### Neue Kopiererfolge an alte Filterdateien anhängen:
    foreach (keys %dirs) {
	my $rsync_filter_path_name = catfile (($dest_root, $_), $rsync_filter_name);
	open RSYNC_FILTER, '>>', catfile (($dest_root, $_), $rsync_filter_name)
	    or die "[" . $$ . "] open" . catfile (($dest_root, $_), $rsync_filter_name) . " failed: $!\n";
	foreach (@{$dirs{$_}}) {
	    if ( !/^\s$/g ) {print RSYNC_FILTER '- /'. $_ . "\n" or die "[" . $$ . "] print failed: $!\n"}
	}
	close RSYNC_FILTER;
    }
    print "[" . $$ . "]{" . (time - $time0) . "} Filterdaten vervollständigt\n" if $debug;
    #### Filterdateien  zur Quelle verschieben:
    $status = getstatus_lock;
    ${$status}{$der_name}{'STATUS'} = "SEND_FILTERFILES";
    ${$status}{$der_name}{'TIME_OF_STATUS'} = time;
    putstatus_unlock $status;
    $rsync->exec( { src => $dest_root, dest => $src_root, 
		    literal => ['--remove-source-files', '--prune-empty-dirs', 
				'--omit-dir-times'], 
		    filter => ['include */', 'include ' . $rsync_filter_name, 'exclude *'] } ) 
	or die "[" . $$ . "] rsync (5) failed: " . $rsync->lastcmd . " $!\n";
    print "[" . $$ . "]{" . (time - $time0) . "} Filterdaten zurückgesendet\n" if $debug;



__END__

debug_print 'RSYNC_EXEC_FORM:' . $rsync_exec_form{'tt11'} ($dest_root) . "\n";
print "Eval EXEC_FORM:\n";
eval $rsync_exec_form{'tt11'} ($dest_root);
print "EVAL RSYNC_EXEC_FORM: $@ \n";
@err = $rsync_tt11->err;
print @err . "(err)\n"; # needs to be 6 (no space left on device) or nothing
print $rsync_tt11->lastcmd . "(lastcmd)\n";




#if ($dest_root and -d $dest_root # sonst: vorsichtshalber abschließende Wiederholung mit neuer $dest_root, s.u.
#    and not stat ($dest_root . $backed_up_file_name)) { # d.h. kopieren verboten, muss erst gelöscht werden

qx(mkdir -p $dest_root/.temp-$src_root);

eval ($rsync_exec_form);
print $@ . "\n";
print $rsync->err . "\n";
print $rsync->lastcmd . "\n";


__END__

#    $rsync->exec( { src => $src_root, dest => $dest_root, 
#		    filter => ['exclude ' . $rsync_filter_name],
#		    literal => ['--existing', '--itemize-changes', '--itemize-changes', 
#				'--log-file=' . $rsync_log_name, '--log-file-format=' . '%i %b %n'] } ) 
#    or die "[" . $$ . "] rsync (1) failed: " . $rsync->lastcmd . " $!\n";
#    print "[" . $$ . "]{" . (time - $time0) . "} Letzte geänderte Messdaten geholt\n" if $debug;
#} else {
#    print "[" . $$ . "]{" . (time - $time0) . "} Keine geänderten Messdaten geholt\n" if $debug;
#}
    

@mount_out = sort qx/mount/;
#### Ziellaufwerk mit ausreichend Platz suchen:
$status = getstatus_lock;
${$status}{$der_name}{'STATUS'} = "GET_SIZE";
${$status}{$der_name}{'TIME_OF_STATUS'} = time;
putstatus_unlock $status;
@destination_blocks = ();
@groessen = ();
foreach $mountpoint (@mountpoints) {
    @destination_free = ();
    @bytes_to_receive = ();
    if ( grep ( m($mountpoint), @mount_out)) { #### $mountpoint ist unter der Ausgabe von mount.
	$df = df($mountpoint, 1);
	unless ($df) { #### sollte eigentlich nicht vorkommen
	    print "[" . $$ . "] Mountpoints prüfen: Kein Filesystem unter " . $mountpoint . ".\n" if $debug;
	    next;
	}
	print "[" . $$ . "] Vorhandener Platz:" . $df->{bavail} . "\n" if $debug;
	$dest_root = $mountpoint . $dest_dir;
	if (stat $dest_root . $backed_up_file_name) { # d.h. kopieren verboten, muss erst gelöscht werden
	    print "[" . $$ . "] Kopieren verboten: " . $dest_root . $backed_up_file_name . " gefunden.\n" if $debug;
	    $dest_root = undef;
	    next;
	}
        #### Größe des Kopiervorhabens ermitteln:
	$status = getstatus_lock;
	$rsync->exec( { src => $src_root, dest => $dest_root, 
			filter => ['dir-merge ' . $rsync_filter_name, 'exclude ' . $rsync_filter_name,
				   'dir-merge,- ' . $copy_postponed_file_name], 
			literal => ['--dry-run', '--stats'] } ) 
	    or die "[" . $$ . "] rsync (2) failed: " . $rsync->lastcmd . " $!\n";
	@ausgabe = grep /Total transferred file size: ([0-9]+) bytes/, @{$rsync->out};
	@ausgabe[0] =~  /Total transferred file size: ([0-9]+) bytes/;
	$groesse = $1;
	push @groessen, $groesse;
	@ausgabe = grep /Number of files transferred: ([0-9]+)/, @{$rsync->out};
	@ausgabe[0] =~  /Number of files transferred: ([0-9]+)/;
	$filezahl = $1;
	print "[" . $$ . "]{" . (time - $time0) . "} groesse:", $groesse, "\n" if $debug;
	print "[" . $$ . "]{" . (time - $time0) . "} filezahl:", $filezahl, "\n" if $debug;
	push @destination_free, $df->{bavail};
	foreach $job (keys %{$status}) {
	    if ( $job ne $der_name &&
		 ${$status}{$job}{'DESTINATION'} eq $dest_root && 
		 ( ${$status}{$job}{'STATUS'} ne 'COMPLETED' ||
		   ${$status}{$job}{'STATUS'} ne 'COMPLETED_WITH_POSTPONEMENTS' ) ) {
		print "\nDER STATUS:" . ${$status}{$job}{'STATUS'} . "($job)" if $debug;
		print "\nDESTINATION_FREE:" . ${$status}{$job}{'DESTINATION_FREE'} if $debug;
		push @destination_free, ${$status}{$job}{'DESTINATION_FREE'};
		push @bytes_to_receive, ${$status}{$job}{'BYTES_TO_RECEIVE'};
	    }
	}
	print Dumper @destination_free, @bytes_to_receive if $debug;
	print "\nMAX:" . max @destination_free if $debug;
	print "\nSUM:" . sum @bytes_to_receive if $debug;
	$free = max (@destination_free) - sum (@bytes_to_receive); # Was die anderen übriggelassen haben
	print "\nFREE:" . $free if $debug;
	if ($free / $hddmem_factor > $groesse) {
	    ${$status}{$der_name}{'DESTINATION'} = $dest_root;
	    ${$status}{$der_name}{'BYTES_TO_RECEIVE'} = $groesse;
	    ${$status}{$der_name}{'FILES_TO_RECEIVE'} = $filezahl;
	    ${$status}{$der_name}{'DESTINATION_FREE'} = $df->{bavail};
	    putstatus_unlock $status;
	    print "[" . $$ . "] Groß genug\n" if $debug;
	    last;
	} else {
	    $dest_root = '';
	    status_unlock;
	    print "[" . $$ . "] Zu klein: " . $mountpoint . "\n" if $debug;
	    ## Zu viele Daten angesammelt:
	    if ($df->{blocks} / $hddmem_factor < $groesse) {
		push @destination_blocks, $df->{blocks} / $hddmem_factor;
		print "[" . $$ . "] Datenmenge größer als ganze Platte: " . 
		    $mountpoint . " hat nur " . ($df->{blocks} / $hddmem_factor) . "\n" if $debug;
	    }
	    next;
	}
	putstatus_unlock $status
    } else { 
	print "[" . $$ . "] " . $mountpoint . " gibt es nicht\n" if $debug; 
    }
}
qx(mkdir $dest_root) unless -d $dest_root;
if (-d $dest_root) {
    #### Messdaten von Quelle holen:
    $status = getstatus_lock;
    ${$status}{$der_name}{'STATUS'} = 'RECEIVE_DATA';
${$status}{$der_name}{'TIME_OF_STATUS'} = time;
    putstatus_unlock $status;
    $rsync->exec( { src => $src_root, dest => $dest_root, outfun => $rsync_outfun, 
		    filter => ['dir-merge ' . $rsync_filter_name, 
			       'exclude ' . $rsync_filter_name,
			       'dir-merge,- ' . $copy_postponed_file_name], 
		    literal => ['--itemize-changes', '--itemize-changes', 
				'--log-file=' . $rsync_log_name, '--log-file-format=' . '%i %b %n'] } ) 
	or die "[" . $$ . "] rsync (3) failed: " . $rsync->lastcmd . " $!\n";
    print "[" . $$ . "]{" . (time - $time0) . "} Messdaten geholt\n" if $debug;
    open RSYNC_LOG, '<', $rsync_log_name or die "[" . $$ . "] open $rsync_log_name failed: $!\n";
    @rsync_log = <RSYNC_LOG>;
    @dateiliste = grep ((!/receiving file list/ )&
			( !/sent [0-9]+ bytes\s+received [0-9]+ bytes\s+total size [0-9]+/ )&
			( !/\/$/ ), @rsync_log); # Nur Dateipfade.
    
    #### Filterdateien von Quelle holen:
    $status = getstatus_lock;
    ${$status}{$der_name}{'STATUS'} = "RECEIVE_FILTERFILES";
    ${$status}{$der_name}{'TIME_OF_STATUS'} = time;
    putstatus_unlock $status;
    $rsync->exec( { src => $src_root, dest => $dest_root, 
		    filter => ['include */', 'include ' . $rsync_filter_name, 'exclude *',
			       'dir-merge,- ' . $copy_postponed_file_name] } )
	or die "[" . $$ . "] rsync (4) failed: " . $rsync->lastcmd . " $!\n";
    print "[" . $$ . "]{" . (time - $time0) . "} Filterdaten geholt\n" if $debug;
    foreach (@dateiliste) {
	/\S+\s\S+\s\[\S+\]\s[><ch\.]f\S+\s[0-9]+\s(.+)/g;
	@tmp = splitpath($1);
	push ( @{$dirs {$tmp[1]}}, $tmp[2] ); # Dirname = Key in $dirs, Referenz auf Filename-Array = Wert
    }
    print "[" . $$ . "]{" . (time - $time0) . "} Dateiliste ausgewertet\n" if $debug;
    #### Neue Kopiererfolge an alte Filterdateien anhängen:
    foreach (keys %dirs) {
	my $rsync_filter_path_name = catfile (($dest_root, $_), $rsync_filter_name);
	open RSYNC_FILTER, '>>', catfile (($dest_root, $_), $rsync_filter_name)
	    or die "[" . $$ . "] open" . catfile (($dest_root, $_), $rsync_filter_name) . " failed: $!\n";
	foreach (@{$dirs{$_}}) {
	    if ( !/^\s$/g ) {print RSYNC_FILTER '- /'. $_ . "\n" or die "[" . $$ . "] print failed: $!\n"}
	}
	close RSYNC_FILTER;
    }
    print "[" . $$ . "]{" . (time - $time0) . "} Filterdaten vervollständigt\n" if $debug;
    #### Filterdateien  zur Quelle verschieben:
    $status = getstatus_lock;
    ${$status}{$der_name}{'STATUS'} = "SEND_FILTERFILES";
    ${$status}{$der_name}{'TIME_OF_STATUS'} = time;
    putstatus_unlock $status;
    $rsync->exec( { src => $dest_root, dest => $src_root, 
		    literal => ['--remove-source-files', '--prune-empty-dirs', 
				'--omit-dir-times'], 
		    filter => ['include */', 'include ' . $rsync_filter_name, 'exclude *'] } ) 
	or die "[" . $$ . "] rsync (5) failed: " . $rsync->lastcmd . " $!\n";
    print "[" . $$ . "]{" . (time - $time0) . "} Filterdaten zurückgesendet\n" if $debug;


#### Aufräumen    
    unlink $rsync_log_name;
    close PROGRESSFILE;
    unlink $progressfile_name;
    close SPEEDFILE;
    unlink $speedfile_name;

#### Nachsehen, ob auf $src_root Verzeichnisse ausgeschlossen wurden:
    $status = getstatus_lock;
    ${$status}{$der_name}{'STATUS'} = "LOOK_FOR_POSTPONEMENTS";
    ${$status}{$der_name}{'TIME_OF_STATUS'} = time;
    putstatus_unlock $status;
    $rsync->exec( { src => $src_root, dest => $dest_root,
		    filter => ['include */', 'include ' . $copy_postponed_file_name,
			       'exclude *'],
		    literal => ['--list-only', '--prune-empty-dirs'] } ) 
	or die "[" . $$ . "] rsync (7) failed: " . $rsync->lastcmd . " $!\n";
    print "[" . $$ . "]{" . (time - $time0) . "} Postponed-Dateien gesucht\n" if $debug;
    # Nur Namen von Verzeichnissen mit $copy_postponed_file_name drin:
    @list_of_postponed = grep s/.*\d\d:\d\d:\d\d\s+(\S.*\S\/)$copy_postponed_file_name$/\1/g , $rsync->out;
    chomp @list_of_postponed;
    $status = getstatus_lock;
    print "Postponed: " . Dumper @list_of_postponed if debug;
    @{${$status}{$der_name}{'LIST_OF_POSTPONED'}} = @list_of_postponed;
    putstatus_unlock $status;

#### Eine wohlgeordnete Welt verlassen:
    $status = getstatus_lock;
    ${$status}{$der_name}{'DISKS_TOO_SMALL_BY'} = 0;
    @{${$status}{$der_name}{'LIST_OF_POSTPONED'}} = @list_of_postponed;
    if (@list_of_postponed) { # Nutzer hat Teile vom Kopieren ausgeschlossen
	${$status}{$der_name}{'STATUS'} = "COMPLETED_WITH_POSTPONEMENTS";
	${$status}{$der_name}{'TIME_OF_STATUS'} = time;
    } else {
	${$status}{$der_name}{'STATUS'} = "COMPLETED";
	${$status}{$der_name}{'TIME_OF_STATUS'} = time;
	${$status}{$der_name}{'START_TIME_OF_LAST_COMPLETED'} = $time0;
    }
    putstatus_unlock $status;
} else {
    die "[" . $$ . "] " . $dest_root . " existiert nicht.\n";
}
