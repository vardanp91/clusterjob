package CJ::Matlab;
# This is part of Clusterjob that handles the collection
# of Matlab results
# Copyright 2015 Hatef Monajemi (monajemi@stanford.edu) 

use strict;
use warnings;
use CJ;
use Data::Dumper;
use feature 'say';



sub check_initialization{
    my ($tag_list,$TOP,$BOT,$verbose) = @_;
    
    my @BOT_lines = split /\n/, $BOT;
   
    
    my @pattern;
    foreach my $tag (@$tag_list){
    # grep the line that has this tag as argument
    push @pattern, "\\(.*\\b$tag\\b\.*\\)\|\\{.*\\b$tag\\b\.*\\}";
    }
    my $pattern = join("\|", @pattern);
    
    my @vars;
    foreach my $line (@BOT_lines) {
    
        if($line =~ /(.*)(${pattern})\s*\={1}/){
            my @tmp  = split "\\(|\\{", $line;
            my $var  = $tmp[0];
            #print "$line\n${pattern}:  $var\n";
            $var =~ s/^\s+|\s+$//g;
            push @vars, $var;
        }
    }
    
    foreach(@vars)
    {
        my $line = &CJ::grep_var_line($_,$TOP);
    }

}





sub build_reproducible_script{
    my ($program, $path, $runflag) = @_;


my $program_script = CJ::readFile("$path/$program");
    
my $rp_program_script =<<RP_PRGRAM;

% CJ has its own randState upon calling
% to reproduce results one needs to set
% the internal State of the global stream
% to the one saved when ruuning the code for
% the fist time;
    
load('CJrandState.mat');
globalStream = RandStream.getGlobalStream;
globalStream.State = CJsavedState;
RP_PRGRAM
  
if($runflag =~ /^par.*/){
$rp_program_script .= "addpath(genpath('../.'));";
}else{
$rp_program_script .= "addpath(genpath('.'));";
}

$rp_program_script .= $program_script ;
    
my $rp_program = "reproduce_$program";
CJ::writeFile("$path/$rp_program", $rp_program_script);


}



sub read_matlab_index_set
{
    my ($forline, $TOP, $verbose) = @_;
    
    chomp($forline);
    $forline = &CJ::Matlab::uncomment_matlab_line($forline);   # uncomment the line so you dont deal with comments. easier parsing;
    
    
    # split at equal sign.
    my @myarray    = split(/\s*=\s*/,$forline);
    my @tag     = split(/\s/,$myarray[0]);
    my $idx_tag = $tag[-1];
    
    
  
    
    my $range = undef;
    # The right of equal sign
    my $right  = $myarray[1];
    
    # see if the forline contains :
    if($right =~ /^[^:]+:[^:]+$/){
        
        my @rightarray = split( /\s*:\s*/, $right, 2 );
        
        my $low =$rightarray[0];
        if(! &CJ::isnumeric($low) ){
            &CJ::err("The lower limit of for MUST be numeric for this version of clusterjob\n");
        }
        
		# remove white space
        $rightarray[1]=~ s/^\s+|\s+$//g;
		
		
        if($rightarray[1] =~ /\s*length\(\s*(.+?)\s*\)/){
            
            #CASE i = 1:length(var);
            # find the variable;
            my ($var) = $rightarray[1] =~ /\s*length\(\s*(.+?)\s*\)/;
            my $this_line = &CJ::grep_var_line($var,$TOP);
            
            #extract the range
            my @this_array    = split(/\s*=\s*/,$this_line);
            
            
            my $numbers;
            if($this_array[1] =~ /\[\s*([^:]+?)\s*\]/){
            ($numbers) = $this_array[1] =~ /\[\s*(.+?)\s*\]/;
            my $floating_pattern = "[-+]?[0-9]*[\.]?[0-9]+(?:[eE][-+]?[0-9]+)?";
            my $fractional_pattern = "(?:${floating_pattern}\/)?${floating_pattern}";
            my @vals = $numbers =~ /[\;\,]?($fractional_pattern)[\;\,]?/g;
             
            my $high = 1+$#vals;
            my @range = ($low..$high);
            $range = join(',',@range);
                
            }
            
           
            
        }elsif($rightarray[1] =~ /\s*(\D+)\s*/) {
            #print "$rightarray[1]"."\n";
            # CASE i = 1:L
            # find the variable;
            
			
            my ($var) = $rightarray[1] =~ /\s*(\w+)\s*/;
			
            my $this_line = &CJ::grep_var_line($var,$TOP);
            
            #extract the range
            my @this_array    = split(/\s*=\s*/,$this_line);
            my ($high) = $this_array[1] =~ /\[?\s*(\d+)\s*\]?/;
            
            
            if(! &CJ::isnumeric($high) ){
                $range = undef;
            }else{
                my @range = ($low..$high);
                $range = join(',',@range);
            }
        }elsif($rightarray[1] =~ /.*(\d+).*/){
            # CASE i = 1:10
            my ($high) = $rightarray[1] =~ /^\s*(\d+).*/;
            my @range = ($low..$high);
            $range = join(',',@range);
            
        }else{
            
            
            $range = undef;
            #&CJ::err("strcuture of for loop not recognized by clusterjob. try rewriting your for loop using 'i = 1:10' structure");
            
        }
        
   
        # Other cases of for loop to be considered.
        
        
        
    }
 

    return ($idx_tag, $range);
}




sub run_matlab_index_interpreter{
    my ($tag_list,$for_lines,$TOP,$verbose) = @_;
    
    
    # Check that the local machine has MATLAB (we currently build package locally!)
    
    my $check_matlab_installed = `source ~/.bashrc ; source ~/.profile; command -v matlab`;
    if($check_matlab_installed eq ""){
    &CJ::err("I require matlab but it's not installed");
    }else{
    &CJ::message("Test passed, Matlab is installed on your machine.");
    }
    

# build a script from top to output the range of index
    
# Add top
my $matlab_interpreter_script=$TOP;
    

    
# Add for lines
foreach my $i (0..$#{$for_lines}){
    my $tag = $tag_list->[$i];
    my $forline = $for_lines->[$i];
    
        # print  "$tag: $forline\n";
    
        my $tag_file = "\'/tmp/$tag\.tmp\'";
$matlab_interpreter_script .=<<MATLAB
$tag\_fid = fopen($tag_file,'w+');
$forline
fprintf($tag\_fid,\'%i\\n\', $tag);
end
fclose($tag\_fid);
MATLAB
}
    #print  "$matlab_interpreter_script\n";
    
    my $name = "CJ_matlab_interpreter_script.m";
    my $path = "/tmp";
    &CJ::writeFile("$path/$name",$matlab_interpreter_script);
    &CJ::message("$name is built in $path");

    
    
my $matlab_interpreter_bash = <<BASH;
#!/bin/bash -l
# dump everything user-generated from top in /tmp
cd /tmp/
source ~/.profile
source ~/.bashrc
    matlab -nodisplay -nodesktop -nosplash  <'$path/$name' &>/tmp/matlab.output    # dump matlab output
BASH

    #my $bash_name = "CJ_matlab_interpreter_bash.sh";
    #my $bash_path = "/tmp";
    #&CJ::writeFile("$bash_path/$bash_name",$matlab_interpreter_bash);
    #&CJ::message("$bash_name is built in $bash_path");

&CJ::message("Invoking matlab to find range of indecies. Please be patient...");
&CJ::my_system("echo $matlab_interpreter_bash", $verbose);
&CJ::message("Closing Matlab session!");
    
# Read the files, and put it into $numbers
# open a hashref
my $range={};
foreach my $tag (@$tag_list){
    my $tag_file = "/tmp/$tag\.tmp";
    my $tmp_array = &CJ::readFile("$tag_file");
    my @tmp_array  = split /\n/,$tmp_array;
    $range->{$tag} = join(',', @tmp_array);
    #print $range->{$tag} . "\n";
}
    return $range;
}













sub uncomment_matlab_line{
    my ($line) = @_;
    $line =~ s/^(?:(?!\').)*\K\%(.*)//;
    return $line;
}









sub make_MAT_collect_script
{
my ($res_filename, $completed_filename, $bqs) = @_;
    
my $collect_filename = "collect_list.txt";
    
my $matlab_collect_script=<<MATLAB;
\% READ completed_list.txt and FIND The counters that need
\% to be read
completed_list = load('$completed_filename');

if(~isempty(completed_list))


\%determine the structre of the output
if(exist('$res_filename', 'file'))
    \% CJ has been called before
    res = load('$res_filename');
    start = 1;
else
    \% Fisrt time CJ is being called
    res = load([num2str(completed_list(1)),'/$res_filename']);
    start = 2;
    
    
    \% delete the line from remaining_filename and add it to collected.
    \%fid = fopen('$completed_filename', 'r') ;               \% Open source file.
    \%fgetl(fid) ;                                            \% Read/discard line.
    \%buffer = fread(fid, Inf) ;                              \% Read rest of the file.
    \%fclose(fid);
    \%delete('$completed_filename');                         \% delete the file
    \%fid = fopen('$completed_filename', 'w')  ;             \% Open destination file.
    \%fwrite(fid, buffer) ;                                  \% Save to file.
    \%fclose(fid) ;
    
    if(~exist('$collect_filename','file'));
    fid = fopen('$collect_filename', 'a+');
    fprintf ( fid, '%d\\n', completed_list(1) );
    fclose(fid);
    end
    
    percent_done = 1/length(completed_list) * 100;
    fprintf('\\n SubPackage %d Collected (%3.2f%%)', completed_list(1), percent_done );

    
end

flds = fields(res);


for idx = start:length(completed_list)
    count  = completed_list(idx);
    newres = load([num2str(count),'/$res_filename']);
    
    for i = 1:length(flds)  \% for all variables
        res.(flds{i}) =  CJ_reduce( res.(flds{i}) ,  newres.(flds{i}) );
    end

\% save after each packgae
save('$res_filename','-struct', 'res');
percent_done = idx/length(completed_list) * 100;
    
\% delete the line from remaining_filename and add it to collected.
\%fid = fopen('$completed_filename', 'r') ;              \% Open source file.
\%fgetl(fid) ;                                      \% Read/discard line.
\%buffer = fread(fid, Inf) ;                        \% Read rest of the file.
\%fclose(fid);
\%delete('$completed_filename');                         \% delete the file
\%fid = fopen('$completed_filename', 'w')  ;             \% Open destination file.
\%fwrite(fid, buffer) ;                             \% Save to file.
\%fclose(fid) ;

if(~exist('$collect_filename','file'));
    error('   CJerr::File $collect_filename is missing. CJ stands in AWE!');
end

fid = fopen('$collect_filename', 'a+');
fprintf ( fid, '%d\\n', count );
fclose(fid);
    
fprintf('\\n SubPackage %d Collected (%3.2f%%)', count, percent_done );
end

   

end

MATLAB




my $HEADER= &CJ::bash_header($bqs);

my $script;
if($bqs eq "SGE"){
$script=<<BASH;
$HEADER
echo starting collection
echo FILE_NAME $res_filename


module load MATLAB-R2014a;
matlab -nosplash -nodisplay <<HERE

$matlab_collect_script

quit;
HERE

echo ending colection;
echo "done"
BASH
}elsif($bqs eq "SLURM"){
$script= <<BASH;
$HEADER
echo starting collection
echo FILE_NAME $res_filename

module load matlab;
matlab -nosplash -nodisplay <<HERE

$matlab_collect_script

quit;
HERE

echo ending colection;
echo "done"
BASH

}

    
    return $script;
}




1;