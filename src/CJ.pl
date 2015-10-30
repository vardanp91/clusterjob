#/usr/bin/perl -w
#
# Copyright (c) 2015 Hatef Monajemi (monajemi@stanford.edu)

use strict;
use lib '/Users/hatef/github_projects/clusterjob/src';  #for testing

use CJ;          # contains essential functions
use CJ::CJVars;  # contains global variables of CJ
use CJ::Matlab;  # Contains Matlab related subs
use CJ::Get;     # Contains Get related subs
use Getopt::Declare;
#use Term::ReadKey;
use Term::ReadLine;
#use Term::ANSIColor qw(:constants); # for changing terminal text colors
use Digest::SHA qw(sha1_hex); # generate hexa-decimal SHA1 PID
use vars qw($message $mem $runtime $dep_folder $verbose $text_header_lines $show_tag $qsub_extra $cmdline);  # options

$::VERSION = &CJ::version_info();





#=========================================
# refresh CJlog before declaring options.
# it keeps updated for each new run
&CJ::my_system("rm $CJlog");
#=========================================


#=========================================
# create .info directory if it doesnt exist
mkdir "$install_dir/.info" unless (-d "$install_dir/.info");

# create history file if it does not exist
if( ! -f $history_file ){
    &CJ::touch($history_file);
    my $header = sprintf("%-15s%-15s%-21s%-10s%-15s%-20s%30s", "count", "date", "package", "action", "machine", "job_id", "message");
    &CJ::add_to_history($header);
}

if( ! -f $cmd_history_file ){
    &CJ::touch($cmd_history_file);
}



# create run_history file if it does not exit
# this file contains more information about a run
# such as where it is saved, etc.

&CJ::touch($run_history_file) unless (-f $run_history_file);
#=========================================


#==========================================
#    Get the command line history
#==========================================
my $cmd    = `ps -o args $$ | grep CJ.pl`;
my @cmd = split(/\s/,$cmd);
$cmdline = "$cmd[0] "." $cmd[1]";
foreach ( @ARGV ) {
    $cmdline .= /\s/ ?   " \"" . $_ . "\"":     " "   . $_;
}



#====================================
#         READ FLAGS
#====================================
$dep_folder = ".";
$mem        = "8G";      # default memeory
$runtime    = "40:00:00";      # default memeory
$message    = "";        # default message
$verbose    = 0;	 # default - redirect to CJlog
$text_header_lines = undef;
$show_tag          = "program";
$qsub_extra        = "";


my $spec = <<'EOSPEC';
      prompt 	    opens CJ prompt command [undocumented]
                     {defer{cj_prompt()}}
     -help 	  Show usage information [undocumented]
                    {defer{&CJ::add_cmd($cmdline);$self->usage(0);}}
     help  	 	  [ditto]  [undocumented]

     -Help  	 	  [ditto]  [undocumented]
     -HELP		  [ditto]  [undocumented]
     -version		Show version info [undocumented]
                    {defer{&CJ::add_cmd($cmdline);$self->version(0);}}
     -Version		  [ditto] [undocumented]
      version		  [ditto] [undocumented]
      Version		  [ditto] [undocumented]
     -v 	          [ditto] [undocumented]
     --v[erbose]	                                  verbose mode [nocase]
                                             {$verbose=1}
     --err[or]	                                          error tag [nocase]
                                             {$show_tag="error"}
     --ls      	                                          list tag [nocase]
                                             {$show_tag="ls"}
     --header [=] <num_lines:+i>	                  number of header lines for reducing text files
                                          {$text_header_lines=$num_lines;}
     -dep          <dep_path>		                  dependency folder path [nocase]
                                              {$dep_folder=$dep_path}
     -m            <msg>	                          reminder message
                                              {$message=$msg}
     -mem          <memory>	                          memory requested [nocase]
                                              {$mem=$memory}
     -runtime      <r_time>	                          run time requested (default=40:00:00) [nocase]
                                              {$runtime=$r_time}
     -alloc[ate]   <resources>	                          machine specific allocation [nocase]
                                          {$qsub_extra=$resources}
     log          [<argin>]	                          historical info -n|pkg|all [nocase]
                                          {defer{&CJ::add_cmd($cmdline); &CJ::show_history($argin) }}
     history      [<argin>]	         [ditto]
     cmd          [<argin>]	                          command history -n|all [nocase]
                                              {defer{ &CJ::show_cmd_history($argin) }}
     clean        [<pkg>]		                  clean certain package [nocase]
                                              {defer{ &CJ::add_cmd($cmdline); &CJ::clean($pkg,$verbose); }}
     state        [<pkg> [/] [<counter>]]	          state of package [nocase]
                                              {defer{ &CJ::add_cmd($cmdline);&CJ::get_state($pkg,$counter) }}
     info         [<pkg>]	                          info of certain package [nocase]
                                              {defer{ &CJ::add_cmd($cmdline);&CJ::show_info($pkg); }}
     show         [<pkg> [/] [<counter>]]	          show program/error of certain package [nocase]
                                              {defer{ &CJ::add_cmd($cmdline);&CJ::show($pkg,$counter,$show_tag) }}
     rerun        [<pkg> [/] [<counter>...]]	          rerun certain (failed) job [nocase]
                                               {defer{&CJ::add_cmd($cmdline);&CJ::rerun($pkg,\@counter,$mem,$runtime,$qsub_extra,$verbose) }}
     run          <code> <cluster>	                  run code on the cluster [nocase]
                                              {my $runflag = "run";
                                                  {defer{&CJ::add_cmd($cmdline); run($cluster,$code,$runflag,$qsub_extra)}}
                                               }
     deploy       <code> <cluster>	                  deploy code on the cluster [nocase]
                                              {my $runflag = "deploy";
                                                  {defer{&CJ::add_cmd($cmdline);run($cluster,$code,$runflag,$qsub_extra)}}
                                               }
     parrun       <code> <cluster>	                  parrun code on the cluster [nocase]
                                              {my $runflag = "parrun";
                                                  {defer{&CJ::add_cmd($cmdline);run($cluster,$code,$runflag,$qsub_extra)}}
                                               }
     pardeploy    <code> <cluster>	                  pardeploy code on the cluster [nocase]
                                              {my $runflag = "pardeploy";
                                                  {defer{&CJ::add_cmd($cmdline);run($cluster,$code,$runflag,$qsub_extra)}}
                                               }
     reduce       <filename> [<pkg>] 	                  reduce results of parrun [nocase]
                                                  {defer{&CJ::add_cmd($cmdline);&CJ::Get::reduce_results($pkg,$filename,$verbose,$text_header_lines)}}
     gather       <pattern>  <dir_name> [<pkg>]	          gather results of parrun [nocase]
                                                  {defer{&CJ::add_cmd($cmdline);&CJ::Get::gather_results($pkg,$pattern,$dir_name,$verbose)}}
     get          [<pkg>]	                          bring results back to local machine [nocase]
                                                  {defer{&CJ::add_cmd($cmdline);&CJ::Get::get_results($pkg,$verbose)}}
     save         <pkg> [<path>]	                  save a package in path [nocase]
                                                  {defer{&CJ::add_cmd($cmdline);  &CJ::save_results($pkg,$path,$verbose)}}
     @<cmd_num:+i>	                                  re-executes a previous command avaiable in command history [nocase]
                                                  {defer{&CJ::reexecute_cmd($cmd_num,$verbose) }}
     <unknown>...	                                  unknown arguments will be send to bash [undocumented]
                                                  {defer{my $cmd = join(" ",@unknown); system("$cmd")}}

EOSPEC

my $opts = Getopt::Declare->new($spec);


#    print "$opts->{'-m'}\n";
#    print "$opts->{'-mem'}\n";
#    print "$text_header_lines\n";
#$opts->usage();





#==========================
#   prompt
#==========================
sub cj_prompt{
    

    my $COLOR = "\033[47;30m";
    my $RESET = "\033[0m";
    
    #my $prompt = "${COLOR}[$localHostName:$localUserName] CJ>$RESET ";

    my $prompt = "[$localHostName:$localUserName] CJ> ";
    print  "$::VERSION\n \n \n";
    
    
    #my $promptsize = `echo -n \"$prompt\" | wc -c | tr -d " "`;
    
    #$promptsize = $promptsize+1;  # I add one white space
   

    my $term = Term::ReadLine->new('CJ shell');
    #$term->ornaments(0);  # disable ornaments.
    
    
    my $exit = 0;
    my @exitarray= qw(exit q quit end);
    my %exithash;
    $exithash{$_} = 1 for (@exitarray);
    
    while (!exists $exithash{my $input = $term->readline($prompt)}) {
        #print WHITE, ON_BLACK $prompt, RESET . " ";
        
          my $perl = `which perl`; chomp($perl);
          my $cmd = "$perl $install_dir/CJ.pl" . " $input";
          system($cmd);
         $term->addhistory($input) if /\S/;
        
        
    }
    
    
#    
#    # Read the key input:
#    
#    while (! $exit){
#        print WHITE, ON_BLACK $prompt, RESET . " ";
#        
#        my $total_record=`grep "." $cmd_history_file | tail -1  | awk \'{print \$1}\' `;
#        if(! $total_record){
#            $total_record = 0;
#        }
#        
#        my $previous_record = $total_record;
#        my $curcol = $promptsize+1;
#        my $keyhash;
#        while((my ($pressedKey, $pressedCode)= each %{$keyhash = ReadControlKey()} )[0] ne "return" )
#        {
#            my $new_record;
#            my $cmd="";
#            my $cmdsize;
#            if($pressedKey eq "up" && ($previous_record gt 1)){
#                $new_record = $previous_record-1;
#                $cmd        = &CJ::get_cmd($new_record, 1);
#                $cmdsize = `echo -n \"$cmd\" | wc -c | tr -d " "`;
#                print "\r\033[K". WHITE, ON_BLACK $prompt, RESET . " " ."$cmd" ;
#                $previous_record = $new_record;
#            }elsif($pressedKey eq "down"  && ($previous_record lt $total_record)){
#                $new_record = $previous_record+1;
#                $cmd        = &CJ::get_cmd($new_record, 1);
#                $cmdsize = `echo -n \"$cmd\" | wc -c | tr -d " "`;
#                print "\r\033[K". WHITE, ON_BLACK $prompt, RESET . " " ."$cmd";
#                $previous_record = $new_record;
#            }
#            
#            my $totalcol = $promptsize + $cmdsize;
#            
#            if($pressedKey eq "right" ){
#            print "\033[C";
#            $curcol = $curcol+1;
#            }
#            if($pressedKey eq "left" && ($curcol gt $promptsize+1) ){
#            print "\033[D";
#            $curcol = $curcol-1;
#    
#            }
#            if($pressedCode eq 127 && ($curcol gt $promptsize+1) ){ #delete decimal
#            print "\033[D";
#            $curcol = $curcol-1;
#            }
#
#        }
#        
#        print "\033[0m\n"; # Clear ANSI attributes
    
#        die;
#        my $input = <STDIN>;
#        $input =~ s/[\n\r\f\t]//g;
#        
#        my @exitarray= qw(exit q quit end);
#        my %exithash;
#        $exithash{$_} = 1 for (@exitarray);
#        
#        if(exists $exithash{$input}){
#            $exit = 1;
#            print RESET;
#        }else{
#            
#        
#            
#            my $perl = `which perl`; chomp($perl);
#            my $cmd = "$perl $install_dir/CJ.pl" . " $input";
#            system($cmd);
#
#        }
#        
#    }
    
}


#
#
#sub ReadControlKey{
#    my $key;
#    ReadMode 4;   # turn off control keys
#    
#    my $chr = ReadKey(0);
#    my $code = ord($chr);
#    if($code==27){
#        my $code2 = ord(ReadKey -1);
#        if($code2 eq 91){
#            my $arrow = ord(ReadKey -1);
#            
#            $key = "up"    if ( $arrow == 65 );
#            $key = "down"  if ( $arrow == 66 );
#            $key = "right" if ( $arrow == 67 );
#            $key = "left"  if ( $arrow == 68 );
#            
#            
#        }else{
#            $key = $chr;
#        }
#    }elsif($code==10){ # enter
#        $key = "return";
#    }else{
#        $key = $chr;
#    }
#    ReadMode 0 ; # Reset the control
#    
#    my %keyhash = ($key => $code);
#
#    return \%keyhash;
#}
#


#========================================================================
#            CLUSTERJOB RUN/DEPLOY/PARRUN
#  ex.  clusterjob run myScript.m sherlock -dep DepFolder
#  ex.  clusterjob run myScript.m sherlock -dep DepFolder -m  "my reminder"
#========================================================================

sub run{
    
    my ($machine,$program, $runflag,$qsub_extra) = @_;
    
    my $BASE = `pwd`;chomp($BASE);   # Base is where program lives!
    
    CJ::message("$runflag"."ing [$program] on [$machine]");
   

    
    
    

    
    
    
#====================================
#         DATE OF CALL
#====================================
my $date = &CJ::date();
    

    
# Find the last number
my $lastnum=`grep "." $history_file | tail -1  | awk \'{print \$1}\' `;
my ($hist_date, $time) = split('\_', $date);
my $history = sprintf("%-15u%-15s",$lastnum+1, $hist_date );
    
    
    
    
my $short_message = substr($message, 0, 30);

    
    
my $ssh      = &CJ::host($machine);
my $account  = $ssh->{account};
my $bqs      = $ssh->{bqs};
my $remotePrefix    = $ssh->{remote_repo};
    
# TO BE IMPLEMENTED
#my $sha_expr = "$localUserName:$localHostname:$program:$account:$date";
#my $PID  = sha1_hex("$sha_expr");
#print "$PID\n";
    
   

#check to see if the file and dep folder exists
    
if(! -e "$BASE/$program" ){
 &CJ::err("$BASE/$program not found");
}
if(! -d "$BASE/$dep_folder" ){
    &CJ::err("Dependency folder $BASE/$dep_folder not found");
}
    
&CJ::message("Base-dir=$BASE");


#=======================================
#       BUILD DOCSTRING
#       WE NAME THE REMOTE FOLDERS
#       BY PROGRAM AND DATE
#       EXAMPLE : MaxEnt/2014DEC02_1426
#=======================================



my $program_name   = &CJ::remove_extention($program);
my $localDir       = "$localPrefix/"."$program_name";
my $local_sep_Dir = "$localDir/" . "$date"  ;
my $saveDir       = "$savePrefix"."$program_name";


#====================================
#     CREATE LOCAL DIRECTORIES
#====================================
# create local directories
if(-d $localPrefix){
    
    mkdir "$localDir" unless (-d $localDir);
    mkdir "$local_sep_Dir" unless (-d $local_sep_Dir);
    
}else{
    # create local Prefix
    mkdir "$localPrefix";
    mkdir "$localDir" unless (-d $localDir);
    mkdir "$local_sep_Dir" unless (-d $local_sep_Dir);
}

    
# cp dependencies
my $cmd   = "cp -r $dep_folder/* $local_sep_Dir/";
&CJ::my_system($cmd,$verbose);


    
#=====================
#  REMOTE DIRECTORIES
#=====================
my $program_name    = &CJ::remove_extention($program);
my $remoteDir       = "$remotePrefix/"."$program_name";
my $remote_sep_Dir = "$remoteDir/" . "$date"  ;

# for creating remote directory
my $outText;
if($bqs eq "SLURM"){
$outText=<<TEXT;
#!/bin/bash -l
if [ ! -d "$remotePrefix" ]; then
mkdir $remotePrefix
fi
mkdir $remoteDir
TEXT
}elsif($bqs eq "SGE"){
$outText=<<TEXT;
#!/bin/bash
#\$ -cwd
#\$ -S /bin/bash
if [ ! -d "$remotePrefix" ]; then
mkdir $remotePrefix
fi
mkdir $remoteDir
TEXT
}else{
&CJ::err("unknown BQS");
}

    

if ($runflag eq "deploy" || $runflag eq "run"){

#============================================
#   COPY ALL NECESSARY FILES INTO THE
#    EXPERIMENT FOLDER
#============================================
   


my $cmd = "cp $BASE/$program $local_sep_Dir/";
&CJ::my_system($cmd,$verbose);
    
CJ::message("Creating reproducible script reproducible_$program");
CJ::Matlab::build_reproducible_script($program, $local_sep_Dir, $runflag);
    

    
    
    
    

#===========================================
# BUILD A BASH WRAPPER
#===========================================
    
  

my $sh_script = make_shell_script($ssh,$program,$date,$bqs);
my $local_sh_path = "$local_sep_Dir/bashMain.sh";
&CJ::writeFile($local_sh_path, $sh_script);

# Build master-script for submission
my $master_script;
$master_script =  &CJ::make_master_script($master_script,$runflag,$program,$date,$bqs,$mem,$runtime,$remote_sep_Dir,$qsub_extra);
    
    

my $local_master_path="$local_sep_Dir/master.sh";
&CJ::writeFile($local_master_path, $master_script);





#==================================
#       PROPAGATE THE FILES
#       AND RUN ON CLUSTER
#==================================
my $tarfile="$date".".tar.gz";
my $cmd="cd $localDir; tar  --exclude '.git' --exclude '*~' --exclude '*.pdf'  -czf $tarfile $date/  ; rm -rf $local_sep_Dir  ; cd $BASE";
&CJ::my_system($cmd,$verbose);

    
# create remote directory  using outText
my $cmd = "ssh $account 'echo `$outText` '  ";
&CJ::my_system($cmd, $verbose);


&CJ::message("Sending package");
# copy tar.gz file to remoteDir
my $cmd = "rsync -avz  ${localDir}/${tarfile} ${account}:$remoteDir/";
&CJ::my_system($cmd,$verbose);


&CJ::message("Submitting package ${date}");
my $cmd = "ssh $account 'source ~/.bashrc;cd $remoteDir; tar -xzvf ${tarfile} ; cd ${date}; bash master.sh > $remote_sep_Dir/qsub.info; sleep 2'";
&CJ::my_system($cmd,$verbose) unless ($runflag eq "deploy");
    

 
# bring the log file
my $qsubfilepath="$remote_sep_Dir/qsub.info";
my $cmd = "rsync -avz $account:$qsubfilepath  $install_dir/.info";
&CJ::my_system($cmd,$verbose) unless ($runflag eq "deploy");

    
    
    
    
    
my $job_id;
if($runflag eq "run"){
# read run info
my $local_qsub_info_file = "$install_dir/.info/"."qsub.info";
    
    my $local_qsub_info_file = "$install_dir/.info/"."qsub.info";
    my $job_ids = &CJ::read_qsub($local_qsub_info_file);
    $job_id = $job_ids->[0]; # there is only one in this case
CJ::message("Job-id: $job_id");
    
#delete the local qsub.info after use
my $cmd = "rm $local_qsub_info_file";
&CJ::my_system($cmd,$verbose);
    
    

$history .= sprintf("%-21s%-10s%-15s%-20s%-30s",$date, $runflag, $machine, $job_id, $short_message);
&CJ::add_to_history($history);
#=================================
# store tarfile info for deletion
# when needed
#=================================

    
}else{
$job_id ="";
$history .= sprintf("%-21s%-10s%-15s%-20s%-30s",$date, $runflag, $machine, " ", $short_message);
&CJ::add_to_history($history);
}

    
    
my $runinfo={
'package'       => ${date},
machine       => ${machine},
account       => ${account},
local_prefix  => ${localPrefix},
local_path    => "${localDir}/${date}",
remote_prefix => ${remotePrefix},
remote_path   => "${remoteDir}/${date}",
job_id        => $job_id,
bqs           => $bqs,
save_prefix   => ${savePrefix},
save_path     => "${saveDir}/${date}",
runflag       => $runflag,
program       => $program,
message       => $message,
};
&CJ::add_to_run_history($runinfo);
    
    
    
my $last_instance=$date;
#$last_instance.=`cat $BASE/$program`;
&CJ::writeFile($last_instance_file, $last_instance);

    
    
    
}elsif($runflag eq "parrun"  || $runflag eq "pardeploy"){
#==========================================
#   clusterjob parrun myscript.m DEP
#
#   this implements parfor in perl so for
#   each grid point, we will have one separate
#   job
#==========================================

# read the script, parse it out and
# find the for loops
my $scriptfile = "$BASE/$program";
  
    
# script lines will have blank lines or comment lines removed;
# ie., all remaining lines are effective codes
# that actually do something.
my $script_lines;
open my $fh, "$scriptfile" or die "Couldn't open file: $!";
while(<$fh>){
    $_ = &CJ::Matlab::uncomment_matlab_line($_);
    if (!/^\s*$/){
        $script_lines .= $_;
    }
}
close $fh;
    
    # this includes fors on one line
    
my @lines = split('\n|;\s*(?=for)', $script_lines);

my @forlines_idx_set;
foreach my $i (0..$#lines){
my $line = $lines[$i];
    if ($line =~ /^\s*(for.*)/ ){
    push @forlines_idx_set, $i;
    }
}
# ==============================================================
# complain if the size of for loops is more than three or
# if they are not consecetive. We do not allow it in clusterjob.
# ==============================================================
if($#forlines_idx_set+1 > 3 || $#forlines_idx_set+1 < 1)
{
 &CJ::err(" 'parrun' does not allow a non-par loop, less than 1 or more than 3 parloops inside the MAIN script.");
}
    
foreach my $i (0..$#forlines_idx_set-1){
if($forlines_idx_set[$i+1] ne $forlines_idx_set[$i]+1){
 &CJ::err("CJ does not allow anything between the parallel for's. try rewriting your loops");
}
}

    
    
my $TOP;
my $FOR;
my $BOT;
    
foreach my $i (0..$forlines_idx_set[0]-1){
$TOP .= "$lines[$i]\n";
}
foreach my $i ($forlines_idx_set[0]..$forlines_idx_set[0]+$#forlines_idx_set){
$FOR .= "$lines[$i]\n";
}
foreach my $i ($forlines_idx_set[0]+$#forlines_idx_set+1..$#lines){
$BOT .= "$lines[$i]\n";
}
    

    
# Determine the tags and ranges of the
# indecies
my @idx_tags;
my @ranges;
my @tags_to_matlab_interpret;
my @forlines_to_matlab_interpret;
    
    
    my @forline_list = split /^/, $FOR;
   
for my $this_forline (@forline_list) {
    
    
    my ($idx_tag, $range) = &CJ::Matlab::read_matlab_index_set($this_forline, $TOP,$verbose);
    
    
    # if we can't establish range, we output undef
    if(defined($range)){
        push @idx_tags, $idx_tag;
        push @ranges, $range;
    }else{
        push @tags_to_matlab_interpret, $idx_tag;
        push @forlines_to_matlab_interpret, $this_forline;
    }
    
}


    
if ( @tags_to_matlab_interpret ) { # if we need to run matlab
    my $range_run_interpret = &CJ::Matlab::run_matlab_index_interpreter(\@tags_to_matlab_interpret,\@forlines_to_matlab_interpret, $TOP, $verbose);
    
    
    for (keys %$range_run_interpret)
    {
    push @idx_tags, $_;
    push @ranges, $range_run_interpret->{$_};
    #print"$_:$range_run_interpret->{$_} \n";
    }
}
    
    
    
#===================================================
#     Check that user has initialized for loop vars
#===================================================
&CJ::Matlab::check_initialization(\@idx_tags,$TOP,$BOT,$verbose);
    
    
    
    
    
    
    
#==============================================
#        MASTER SCRIPT
#==============================================
    
    
    
my $nloops = $#forlines_idx_set+1;

my $counter = 0;   # counter gives the total number of jobs submited: (1..$counter)

my $master_script;
if($nloops eq 1){

    
            # parallel vars
            my @idx_0 = split(',', $ranges[0]);
            
            foreach my $v0 (@idx_0){
                  $counter = $counter+1;
                    
                    #============================================
                    #     BUILD EXP FOR this (v0)
                    #============================================
                    
                    
                    my $INPUT;
                    $INPUT .= "if ($idx_tags[0]~=$v0); continue;end";
                    my $new_script = "$TOP \n $FOR \n $INPUT \n $BOT";
                    undef $INPUT;                   #undef INPUT for the next run
                    
                    #============================================
                    #   COPY ALL NECESSARY FILES INTO THE
                    #   EXPERIMENTS FOLDER
                    #============================================
                    
                
                    mkdir "$local_sep_Dir/$counter";
                    
                    my $this_path  = "$local_sep_Dir/$counter/$program";
                    &CJ::writeFile($this_path,$new_script);
                
                    # build reproducible script for each run
                    CJ::Matlab::build_reproducible_script($program, "$local_sep_Dir/$counter", $runflag);
                
                
                    
                    
                    # build bashMain.sh for each parallel package
                    my $remote_par_sep_dir = "$remote_sep_Dir/$counter";
                    my $sh_script = make_par_shell_script($ssh,$program,$date,$bqs,$counter,$remote_par_sep_dir);
                    my $local_sh_path = "$local_sep_Dir/$counter/bashMain.sh";
                    &CJ::writeFile($local_sh_path, $sh_script);
                
                $master_script =  &CJ::make_master_script($master_script,$runflag,$program,$date,$bqs,$mem,$runtime,$remote_sep_Dir,$qsub_extra,$counter);
                } #v0
    

}elsif($nloops eq 2){

  
    
        # parallel vars
        my @idx_0 = split(',', $ranges[0]);
        my @idx_1 = split(',', $ranges[1]);
        
        
        foreach my $v0 (@idx_0){
            foreach my $v1 (@idx_1){
            
                $counter = $counter+1;
                
                #============================================
                #     BUILD EXP FOR this (v0,v1)
                #============================================
                
                
                my $INPUT;
                $INPUT .= "if ($idx_tags[0]~=$v0 || $idx_tags[1]~=$v1 ); continue;end";
                my $new_script = "$TOP \n $FOR \n $INPUT \n $BOT";
                undef $INPUT;                   #undef INPUT for the next run
               
                #============================================
                #   COPY ALL NECESSARY FILES INTO THE
                #   EXPERIMENTS FOLDER
                #============================================
                
                
                mkdir "$local_sep_Dir/$counter";
                my $this_path  = "$local_sep_Dir/$counter/$program";
                &CJ::writeFile($this_path,$new_script);
                # build reproducible script for each run
                CJ::Matlab::build_reproducible_script($program,  "$local_sep_Dir/$counter", $runflag);

                
                
                # build bashMain.sh for each parallel package
                my $remote_par_sep_dir = "$remote_sep_Dir/$counter";
                my $sh_script = make_par_shell_script($ssh,$program,$date,$bqs,$counter, $remote_par_sep_dir);
                my $local_sh_path = "$local_sep_Dir/$counter/bashMain.sh";
                &CJ::writeFile($local_sh_path, $sh_script);
                
                $master_script =  &CJ::make_master_script($master_script,$runflag,$program,$date,$bqs,$mem,$runtime,$remote_sep_Dir,$qsub_extra,$counter);
            } #v0
        } #v1
    

}elsif($nloops eq 3){
    
    
    
        # parallel vars
        my @idx_0 = split(',', $ranges[0]);
        my @idx_1 = split(',', $ranges[1]);
        my @idx_2 = split(',', $ranges[2]);
        foreach my $v0 (@idx_0){
            foreach my $v1 (@idx_1){
                foreach my $v2 (@idx_2){
                $counter = $counter+1;
                
                #============================================
                #     BUILD EXP FOR this (v0,v1)
                #============================================
                
                
                my $INPUT;
                $INPUT .= "if ($idx_tags[0]~=$v0 || $idx_tags[1]~=$v1  || $idx_tags[2]~=$v2); continue;end";
                my $new_script = "$TOP \n $FOR \n $INPUT \n $BOT";
                undef $INPUT;                   #undef INPUT for the next run
                
                #============================================
                #   COPY ALL NECESSARY FILES INTO THE
                #   EXPERIMENTS FOLDER
                #============================================
                
                
                mkdir "$local_sep_Dir/$counter";
                    
                my $this_path  = "$local_sep_Dir/$counter/$program";
                &CJ::writeFile($this_path,$new_script);
                # build reproducible script for each run
                CJ::Matlab::build_reproducible_script($program, "$local_sep_Dir/$counter", $runflag);

                
                
                # build bashMain.sh for each parallel package
                my $remote_par_sep_dir = "$remote_sep_Dir/$counter";
                my $sh_script = make_par_shell_script($ssh,$program,$date,$bqs,$counter, $remote_par_sep_dir);
                my $local_sh_path = "$local_sep_Dir/$counter/bashMain.sh";
                &CJ::writeFile($local_sh_path, $sh_script);
                
                
                $master_script =  &CJ::make_master_script($master_script,$runflag,$program,$date,$bqs,$mem,$runtime,$remote_sep_Dir,$qsub_extra,$counter);
                
        } #v0
        } #v1
        } #v2
        
        
    
    
    


}else{
    &CJ::err("Max number of parallel variables exceeded; $nloops > 3 ");
}
    

    
#============================================
#   COPY ALL NECESSARY FILES INTO THE
#    EXPERIMENT FOLDER
#============================================
my $cmd = "cp $BASE/$program $local_sep_Dir/";
&CJ::my_system($cmd,$verbose);
    
    
#===================================
# write out developed master script
#===================================
my $local_master_path="$local_sep_Dir/master.sh";
    &CJ::writeFile($local_master_path, $master_script);
    

#==================================
#       PROPAGATE THE FILES
#       AND RUN ON CLUSTER
#==================================
my $tarfile="$date".".tar.gz";
my $cmd="cd $localDir; tar --exclude '.git' --exclude '*~' --exclude '*.pdf' -czf  $tarfile $date/   ; rm -rf $local_sep_Dir  ; cd $BASE";
&CJ::my_system($cmd,$verbose);


# create remote directory  using outText
my $cmd = "ssh $account 'echo `$outText` '  ";
&CJ::my_system($cmd,$verbose);

&CJ::message("Sending package");
# copy tar.gz file to remoteDir
my $cmd = "rsync -arvz  ${localDir}/${tarfile} ${account}:$remoteDir/";
&CJ::my_system($cmd,$verbose);


&CJ::message("Submitting job(s)");
my $cmd = "ssh $account 'source ~/.bashrc;cd $remoteDir; tar -xzf ${tarfile} ; cd ${date}; bash -l master.sh > $remote_sep_Dir/qsub.info; sleep 2'";
&CJ::my_system($cmd,$verbose) unless ($runflag eq "pardeploy");
 

    
# bring the log file
my $qsubfilepath="$remote_sep_Dir/qsub.info";
my $cmd = "rsync -avz $account:$qsubfilepath  $install_dir/.info/";
&CJ::my_system($cmd,$verbose) unless ($runflag eq "pardeploy");
    

    
my @job_ids;
my $job_id;
if($runflag eq "parrun"){
    # read run info
    my $local_qsub_info_file = "$install_dir/.info/"."qsub.info";
    my $job_ids = &CJ::read_qsub($local_qsub_info_file);
    $job_id = join(',', @{$job_ids});

    
&CJ::message("Job-ids: $job_ids->[0]-$job_ids->[-1]");
    
#delete the local qsub.info after use
my $cmd = "rm $local_qsub_info_file";
&CJ::my_system($cmd,$verbose);
    
    


$history .= sprintf("%-21s%-10s%-15s%-20s%-30s",$date, $runflag, $machine, "$job_ids->[0]-$job_ids->[-1]", $short_message);
&CJ::add_to_history($history);
    
    
}else{
$job_id = "";
$history .= sprintf("%-21s%-10s%-15s%-20s%-30s",$date, $runflag, $machine, " ", $short_message);
&CJ::add_to_history($history);
}



    
my $runinfo={
'package'       => ${date},
machine       => ${machine},
account       => ${account},
local_prefix  => ${localPrefix},
local_path    => "${localDir}/${date}",
remote_prefix => ${remotePrefix},
remote_path   => "${remoteDir}/${date}",
job_id        => $job_id,
bqs           => $bqs,
save_prefix   => ${savePrefix},
save_path     => "${saveDir}/${date}",
runflag       => $runflag,
program       => $program,
message       => $message,
};
&CJ::add_to_run_history($runinfo);

    
    
my $last_instance=${date};
#$last_instance.=`cat $BASE/$program`;
&CJ::writeFile($last_instance_file, $last_instance);
    

}else{
&CJ::err("Runflag $runflag was not recognized");
}




    
    exit 0;
    
    
}
    
    



#====================================
#       BUILD A BASH WRAPPER
#====================================

sub make_shell_script
    {
        my ($ssh,$program,$date,$bqs) = @_;

        
        
my $sh_script;

if($bqs eq "SGE"){
$sh_script=<<'HEAD'
#!/bin/bash
#\$ -cwd
#\$ -S /bin/bash
    

echo JOB_ID $JOB_ID
echo WORKDIR $SGE_O_WORKDIR
DIR=`pwd`
HEAD
    
}elsif($bqs eq "SLURM"){
$sh_script=<<'HEAD'
#!/bin/bash -l
echo JOB_ID $SLURM_JOBID
echo WORKDIR $SLURM_SUBMIT_DIR
DIR=`pwd`
HEAD
}else{
&CJ::err("unknown BQS");
}
 
$sh_script.= <<'MID';
PROGRAM="<PROGRAM>";
DATE=<DATE>;
cd $DIR;
mkdir scripts
mkdir logs
SHELLSCRIPT=${DIR}/scripts/CJ.runProgram.${DATE}.sh;
LOGFILE=${DIR}/logs/CJ.runProgram.${DATE}.log;
MID

if($bqs eq "SGE"){
$sh_script.= <<'BASH';
cat <<THERE > $SHELLSCRIPT
#! /bin/bash
#$ -cwd
#$ -R y
#$ -S /bin/bash

echo starting job $SHELLSCRIPT
echo JOB_ID \$JOB_ID
echo WORKDIR \$SGE_O_WORKDIR
date
cd $DIR

module load MATLAB-R2014b
matlab -nosplash -nodisplay <<HERE
<MATPATH>

% make sure each run has different random number stream
myversion = version;
mydate = date;
RandStream.setGlobalStream(RandStream('mt19937ar','seed', sum(100*clock)));
globalStream = RandStream.getGlobalStream;
CJsavedState = globalStream.State;
fname = sprintf('CJrandState.mat');
save(fname,'myversion','mydate', 'CJsavedState');
cd $DIR
run('${PROGRAM}');
quit;
HERE

echo ending job \$SHELLSCRIPT
echo JOB_ID \$JOB_ID
date
echo "done"
THERE
    
chmod a+x $SHELLSCRIPT
bash $SHELLSCRIPT > $LOGFILE
    
BASH
}elsif($bqs eq "SLURM"){
$sh_script.= <<'BASH';
cat <<THERE > $SHELLSCRIPT
#! /bin/bash -l

echo starting job \$SHELLSCRIPT
echo JOB_ID \$SLURM_JOBID
echo WORKDIR \$SLURM_SUBMIT_DIR
date
cd $DIR

module load matlab\/R2014b
matlab -nosplash -nodisplay <<HERE
<MATPATH>
% make sure each run has different random number stream
myversion = version;
mydate = date;
RandStream.setGlobalStream(RandStream('mt19937ar','seed', sum(100*clock)));
globalStream = RandStream.getGlobalStream;
CJsavedState = globalStream.State;
fname = sprintf('CJrandState.mat');
save(fname, 'myversion' ,'mydate', 'CJsavedState');
cd $DIR
run('${PROGRAM}');
quit;
HERE
    
echo ending job \$SHELLSCRIPT
echo JOB_ID \$SLURM_JOBID
date
echo "done"
THERE
    
chmod a+x $SHELLSCRIPT
bash $SHELLSCRIPT > $LOGFILE
    
BASH
}

        
        
my $pathText.=<<MATLAB;
        
% add user defined path
addpath $ssh->{matlib} -begin

% generate recursive path
addpath(genpath('.'));
    
try
    cvx_setup;
    cvx_quiet(true)
    % Find and add Sedumi Path for machines that have CVX installed
        cvx_path = which('cvx_setup.m');
    oldpath = textscan( cvx_path, '%s', 'Delimiter', '/');
    newpath = horzcat(oldpath{:});
    sedumi_path = [sprintf('%s/', newpath{1:end-1}) 'sedumi'];
    addpath(sedumi_path)
    
catch
    warning('CVX not enabled. Please set CVX path in .ssh_config if you need CVX for your jobs');
end

MATLAB

        
        
        
        
        
        
$sh_script =~ s|<PROGRAM>|$program|;
$sh_script =~ s|<DATE>|$date|;
$sh_script =~ s|<MATPATH>|$pathText|;
        
return $sh_script;
}
        
        

# parallel shell script
#====================================
#       BUILD A PARALLEL BASH WRAPPER
#====================================

sub make_par_shell_script
{
my ($ssh,$program,$date,$bqs,$counter,$remote_path) = @_;

my $sh_script;
if($bqs eq "SGE"){
    
$sh_script=<<'HEAD'
#!/bin/bash -l
#\$ -cwd
#\$ -S /bin/bash

echo JOB_ID $JOB_ID
echo WORKDIR $SGE_O_WORKDIR
DIR=<remote_path>
HEAD

}elsif($bqs eq "SLURM"){
$sh_script=<<'HEAD'
#!/bin/bash -l
echo JOB_ID $SLURM_JOBID
echo WORKDIR $SLURM_SUBMIT_DIR
DIR=<remote_path>
HEAD
}else{
&CJ::err("unknown BQS");
}
    

$sh_script.= <<'MID';
PROGRAM="<PROGRAM>";
DATE=<DATE>;
COUNTER=<COUNTER>;
cd $DIR;
mkdir scripts
mkdir logs
SHELLSCRIPT=${DIR}/scripts/CJ.runProgram.${DATE}.${COUNTER}.sh;
LOGFILE=${DIR}/logs/CJ.runProgram.${DATE}.${COUNTER}.log;
MID

if($bqs eq "SGE"){
$sh_script.= <<'BASH';
cat <<THERE > $SHELLSCRIPT
#! /bin/bash -l
#$ -cwd
#$ -R y
#$ -S /bin/bash

echo starting job $SHELLSCRIPT
echo JOB_ID \$JOB_ID
echo WORKDIR \$SGE_O_WORKDIR
date
cd $DIR

module load MATLAB-R2014b
matlab -nosplash -nodisplay <<HERE
<MATPATH>

    
% add path for parrun
oldpath = textscan('$DIR', '%s', 'Delimiter', '/');
newpath = horzcat(oldpath{:});
bin_path = sprintf('%s/', newpath{1:end-1});
addpath(genpath(bin_path));  % recursive path
    
    
% make sure each run has different random number stream
myversion = version;
mydate = date;
    
% To get different Randstate for different jobs
rng(${COUNTER})
seed = sum(100*clock) + randi(10^6);
RandStream.setGlobalStream(RandStream('mt19937ar','seed', seed));
globalStream = RandStream.getGlobalStream;
CJsavedState = globalStream.State;
fname = sprintf('CJrandState.mat');
save(fname, 'myversion','mydate', 'CJsavedState');
cd $DIR
run('${PROGRAM}');
quit;
HERE

echo ending job \$SHELLSCRIPT
echo JOB_ID \$JOB_ID
date
echo "done"
THERE

chmod a+x $SHELLSCRIPT
bash $SHELLSCRIPT > $LOGFILE

BASH
}elsif($bqs eq "SLURM"){
$sh_script.= <<'BASH';
cat <<THERE > $SHELLSCRIPT
#! /bin/bash -l

echo starting job \$SHELLSCRIPT
echo JOB_ID \$SLURM_JOBID
echo WORKDIR \$SLURM_SUBMIT_DIR
date
cd $DIR

module load matlab\/R2014b
matlab -nosplash -nodisplay <<HERE
<MATPATH>

    
% add path for parrun
oldpath = textscan('$DIR', '%s', 'Delimiter', '/');
newpath = horzcat(oldpath{:});
bin_path = sprintf('%s/', newpath{1:end-1});
addpath(genpath(bin_path));
    
    
% make sure each run has different random number stream
myversion = version;
mydate = date;
% To get different Randstate for different jobs
rng(${COUNTER})
seed = sum(100*clock) + randi(10^6);
RandStream.setGlobalStream(RandStream('mt19937ar','seed', seed));
globalStream = RandStream.getGlobalStream;
CJsavedState = globalStream.State;
fname = sprintf('CJrandState.mat');
save(fname,'myversion', 'mydate', 'CJsavedState');
cd $DIR
run('${PROGRAM}');
quit;
HERE

echo ending job \$SHELLSCRIPT
echo JOB_ID \$SLURM_JOBID
date
echo "done"
THERE

chmod a+x $SHELLSCRIPT
bash $SHELLSCRIPT > $LOGFILE


BASH
}

my $pathText.=<<MATLAB;
    
% add user defined path
addpath $ssh->{matlib} -begin

% generate recursive path
addpath(genpath('.'));

try
cvx_setup;
cvx_quiet(true)
% Find and add Sedumi Path for machines that have CVX installed
    cvx_path = which('cvx_setup.m');
oldpath = textscan( cvx_path, '%s', 'Delimiter', '/');
newpath = horzcat(oldpath{:});
sedumi_path = [sprintf('%s/', newpath{1:end-1}) 'sedumi'];
addpath(sedumi_path)

catch
warning('CVX not enabled. Please set CVX path in .ssh_config if you need CVX for your jobs');
end

MATLAB




$sh_script =~ s|<PROGRAM>|$program|;
$sh_script =~ s|<DATE>|$date|;
$sh_script =~ s|<COUNTER>|$counter|;
$sh_script =~ s|<MATPATH>|$pathText|;
$sh_script =~ s|<remote_path>|$remote_path|;
    

return $sh_script;
}

























#====================================
#       USEFUL SUBs
#====================================
        





#sub matlab_var
#{
#    my ($s) = @_;
#
#   if(&CJ::isnumeric($s)){
#        return "[$s]";
#    }else{
#        return "\'$s\'";
#    }
#
#}















