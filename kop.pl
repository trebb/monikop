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


$debug = 2;
sub debug_print { print "@_" if $debug};

# Write @content to a file with a name starting with $filename
# and ending with _a or _b. Leave at least one such file, even if interrupted.
sub safe_write {
    my ($filename, @content) = @_;
    my $filename_a = $filename;
    my $filename_b = $filename . "_bak";
    my $filename_unfinished = "unfinished_" . $filename;
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
    my $filename_b = $filename . "_bak";
    if (stat $filename_b) { qx(cp $filename_b $filename_a)}
}

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
    my $filename_b = $filename . "_bak";
    if (stat $filename_a) { my $filename = $filename_a }
    elsif (stat $filename_b) { my $filename = $filename_b }
    else { return () };
    print "SAFE_READ: $filename";
    read_list $filename;
}

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


@dest_roots = ( 'tt6', 'tt7', 'tt8' );
$dest_root = 'tt6';
@source_roots = ( 'tt11', 'tt10', 'tt9');
#@source_roots = ( 'tt11');
$source_root = 'tt11';
$progressfile_name = "progress_";
$speedfile_name = "speed_";

sub  rsync_preparation_form {
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
	   'open PROGRESSFILE_', $source, ', \'>\', ', $progressfile_name, $source,
	   '    or die "[" . $$ . "] open ', $progressfile_name, $source, ' failed: $!\n";',
	   "\n",
	   'open SPEEDFILE_', $source, ', \'>\', ', $speedfile_name, $source,
	   '    or die "[" . $$ . "] open ', $speedfile_name, $source, ' failed: $!\n";',
	   "\n",
##########  Run rsync
	   '$rsync_', $source, ' = File::Rsync->new; ',
	   '$rsync_exec_form{\'', $source, '\'} = sub ',
	   '{ ',
	   '    my ($destination) = @_;',
	   '    \'$rsync_', $source, '->exec(',
	   '        {',
	   '            src => \\\'', $source, '/\\\', ',
	   '            dest => \\\'\' . $destination . \'/\\\', ',
	   '            outfun => $rsync_outfun_', $source, ', ', 
	   '            progress => 1, debug => 0, verbose => 0, ',
#	   '    	filter => [\\\'dir-merge finished_', $source, '\\\',',
#	   '                       \\\'exclude finished_', $source, '\\\'], ',
	   '    	filter => [\\\'exclude finished_', $source, '\\\'], ',
	   '            literal => [\\\'--temp-dir=.temp-', $source, '\\\', ',
	   '                        \\\'--recursive\\\', \\\'--times\\\', ',
	   '                        \\\'--prune-empty-dirs\\\', ',
	   '                        \\\'--log-file-format=%i %b %n\\\', ',
	                    join (', ', map { '\\\'--compare-dest=/root/' . $_ . '/\\\'' }
	        		      ( @dest_roots )),
	   '                      , \\\'--log-file=', 'log.', $source, '\\\'] ',
	   '        }',
	   '    );\' ',
	   '};',
	   "\n",
##########  Get directory from source
	   '$rsync_dir_', $source, ' = File::Rsync->new; ',
	   '$rsync_dir_exec_form{\'', $source, '\'} = sub ',
	   '{ ',
	   '    \'$rsync_dir_', $source, '->list(',
	   '        {',
	   '            src => \\\'', $source, '/\\\', ',
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
	debug_print "######################################\n";
	debug_print "RSYNC_EXEC_FORM $source, $_:" . $rsync_exec_form{$source} ($_) . "\n";
	debug_print "######################################\n";
	qx(mkdir -p $_/.temp-$source);
	eval ($rsync_exec_form{$source} ($_));
	debug_print "EVAL RSYNC_EXEC_FORM $source, $_: $@ \n";
    } @destinations;
}

# Set up and start things per source_root:
map {
    debug_print 'rsync_preparation_form:' . rsync_preparation_form ($_). "\n";
    eval rsync_preparation_form $_;
    debug_print "EVAL RSYNC_PREPARATION_FORM $_: $@ \n";
    debug_print 'rsync_dir_exec_form $_:'. $rsync_dir_exec_form{$_} () . "\n";
    reassure_safe_file ("finished" . $_);
    rsync_someplace $_, @dest_roots; # TODO: rotate @dest_roots for load balancing: push (shift ...)...
#### Test/exploration
    my $rsync_log_name = "log." . $_;
    my $finished_name = "finished_" . $_;
    my @rsync_log = read_list $rsync_log_name;
    my @finished = read_list $finished_name;
    my %filelist = map {$_, 42} @finished, grep (s/[\d\/\s:\[\]]+ [>c\.][fd]\S{9} \d+ (.*)/$1/
						      , @rsync_log);
    my @filelist = sort keys %filelist;
    safe_write $finished_name, @filelist;
    debug_print @filelist;

    my @source_dir = grep (s/[drwx-]+\s+\d+ [\d\/]+ [\d:]+ (.*)/$1/ , eval $rsync_dir_exec_form{$_} ());
    debug_print "EVAL RSYNC_DIR_EXEC_FORM $_: $@ \n";
    debug_print "SOURCE_DIR:\n";
    debug_print @source_dir;

    my @intersection = ();
    my %count = ();
    foreach $element (@source_dir, @filelist) { $count{$element}++ }
    foreach $element (keys %count) {
	push @intersection, $element if $count{$element} > 1;
    }
    @intersection = sort @intersection;
    debug_print "INTERSECTION:\n";
    debug_print @intersection;
    safe_write $finished_name, @intersection;
    unlink $rsync_log_name;

    debug_print "#######################################################################\n";
} @source_roots;

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

__END__



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
print "\n[" . $$ . "] Hierhin wird gespeichert " . "$dest_root\n" if $debug;
unless ($dest_root) { # Kein passendes Speicherziel gefunden
    if (@destination_blocks) { # Datenmengen größer als Platten
        #### Auf $src_root ausschließbare Verzeichnisse suchen:
	$status = getstatus_lock;
	${$status}{$der_name}{'STATUS'} = "LOOK_FOR_POSTPONEABLES";
	${$status}{$der_name}{'TIME_OF_STATUS'} = time;
	putstatus_unlock $status;
	$rsync->exec( { src => $src_root, dest => 'dummy',
			filter => ['include /*/',
				   'exclude *'],
			literal => ['--list-only', '--no-recursive'] } ) 
	    or die "[" . $$ . "] rsync (2.a) failed: " . $rsync->lastcmd . " $!\n";
	print "[" . $$ . "]{" . (time - $time0) . "} Postponed-Dateien gesucht\n" if $debug;
	# Nur Namen von ausschließbaren Verzeichnissen:
	@list_of_postponeables = grep s/.*\d\d:\d\d:\d\d\s+(\S.*\S)$/\1\//g, $rsync->out;
	chomp @list_of_postponeables;
	$status = getstatus_lock;
	print "Postponeables: " . Dumper @list_of_postponeables if debug;
	@{${$status}{$der_name}{'LIST_OF_POSTPONEABLES'}} = @list_of_postponeables;
	${$status}{$der_name}{'STATUS'} = 'ERROR:DISKS_TOO_SMALL';
	putstatus_unlock $status;
	print "\n[" . $$ . "] DESTINATION_BLOCKS: " . Dumper @destination_blocks if $debug;
	print "\n[" . $$ . "] GROESSEN: " . Dumper @groessen if $debug;
    } else { # Platten einfach nur zu voll
	$status = getstatus_lock;
	${$status}{$der_name}{'STATUS'} = 'ERROR:NO_ROOM_LEFT';
	putstatus_unlock $status;
    }
    #### Nachsehen, ob auf $src_root schon Verzeichnisse ausgeschlossen sind:
    $rsync->exec( { src => $src_root, dest => 'dummy',
		    filter => ['include */', 'include ' . $copy_postponed_file_name,
			       'exclude *'],
		    literal => ['--list-only', '--prune-empty-dirs'] } ) 
	or die "[" . $$ . "] rsync (7) failed: " . $rsync->lastcmd . " $!\n";
    print "[" . $$ . "]{" . (time - $time0) . "} Postponed-Dateien gesucht\n" if $debug;
    # Nur Namen von Verzeichnissen mit $copy_postponed_file_name drin:
    @list_of_postponed = grep s/.*\d\d:\d\d:\d\d\s+(\S.*\S\/)$copy_postponed_file_name$/\1/g , $rsync->out;
    chomp @list_of_postponed;
    print "Postponed: " . Dumper @list_of_postponed if debug;
    $status = getstatus_lock;
    ${$status}{$der_name}{'DESTINATION'} = $dest_root;
    ${$status}{$der_name}{'BYTES_TO_RECEIVE'} = max @groessen;
    ${$status}{$der_name}{'FILES_TO_RECEIVE'} = $filezahl;
    ${$status}{$der_name}{'DESTINATION_FREE'} = 0;
    ${$status}{$der_name}{'TIME_OF_STATUS'} = time;
    ${$status}{$der_name}{'DISKS_TOO_SMALL_BY'} = max (@groessen) - min (@destination_blocks);
    @{${$status}{$der_name}{'LIST_OF_POSTPONED'}} = @list_of_postponed;
    putstatus_unlock $status;
    die "[" . $$ . "] Keinen ausreichenden Platz für die zu kopierenden $groesse Bytes gefunden.\n";
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

#### Die (wenigen) Messdaten holen, die, weil schon mal kopiert, per 
####  Datei $rsync_filter_name ausgeschlossen sind, sich aber noch geändert haben:
####  (Haben wir schon anfangs mit alter $dest_root gemacht, jetzt vorsichtshalber
####  mit neuer $dest_root)
    $status = getstatus_lock;
    ${$status}{$der_name}{'STATUS'} = "GET_NEW_LEFTOVER";
    ${$status}{$der_name}{'TIME_OF_STATUS'} = time;
    putstatus_unlock $status;
    $dest_root = ${$status}{$der_name}{'DESTINATION'};
    $rsync->exec( { src => $src_root, dest => $dest_root, 
		    filter => ['exclude ' . $rsync_filter_name,
			       'dir-merge,- ' . $copy_postponed_file_name],
		    literal => ['--existing', '--itemize-changes', '--itemize-changes', 
				'--log-file=' . $rsync_log_name, '--log-file-format=' . '%i %b %n'] } ) 
	or die "[" . $$ . "] rsync (6) failed: " . $rsync->lastcmd . " $!\n";
    print "[" . $$ . "]{" . (time - $time0) . "} Letzte geänderte Messdaten geholt\n" if $debug;

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
