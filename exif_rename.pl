#!/usr/bin/perl -w
##############################################################################
# author:           Alex Berger
# Copyright:        (C) @lex Berger
# function:         this script will rename images, numerate them, move them
#                   into subdirectories.
#                   It will also convert proprietary raw files to dng and 
#                   delete the original raw files after that if conversion
#                   went well.
# version:          V1.0 03/20/2016 
# changed by:       Alex Berger
###############################################################################

use strict;
use warnings;
use POSIX ":sys_wait_h";
#use lib "$ENV{'HOME'}/lx/bin/lib";
#use lib "$ENV{'HOME'}/Pictures/bin";
use lib "/usr/bin/lib";
use Image::ExifTool;
use Getopt::Std;
use Cwd;
use Cwd 'chdir';
use vars qw( $opt_h $opt_d $testing );
use File::Copy;
use File::Basename;
use File::Find;
use File::Path qw(remove_tree rmtree);
use Switch;
use Sys::Info;
use Sys::Info::Constants qw( :device_cpu );
use Data::Dumper;
use constant false => 0;
use constant true  => 1;

# ----------- vars just for testing -------------------------------------------
#$testing = 1;
# ----------- vars just for testing -------------------------------------------

getopt('d');

#--------------------------------------------------------------------------
# variables definition
#--------------------------------------------------------------------------
my (
$abk_canon_mod,         # abk canon camera model modifications
$dir_name,              # directory name
$dir_pattern,           # directory pattern
$dir_prefix,            # directory prefix
$dng_converter,         # dng converter app
$dng_ext,               # dng extantion
%errors,                # error code
$files2exclude,         # files to exclude from search
$hash_ref,              # hash reference to the read structure
$hash_new_names,        # hash with new names
@img_ext,               # image extension name
$info,
$info_cpu,
$info_cpu_ht,
%options,               # options for the cpu
@raw_ext,               # raw files extension
$raw_hash,              #reference to hash or raw directories
$raw_target,            # name of the raw target file extension
$sep_sign,              # separation sign
$shell_var,             # shell type
$sub_dirs,              # sub directories to create
$this_file,             # the name of this file/ program
%thmb,                  # properties for thumbnail files
$unix_like              # 1 if unix like system, 0 if not
);


#--------------------------------------------------------------------------
# variables initialisation
#--------------------------------------------------------------------------
$abk_canon_mod = true;
$dir_pattern  = '^\d{8}_\w+';
%errors       = (
  'chDir'     => 'cannot change to the directory',
  'format'    => 'does not have the expected format',
  'openDir'   => 'can not open the directory',
  'openFile'  => 'can not open the file:',
  'createFile'=> 'can not create the file:',
);
$files2exclude = "Adobe Bridge Cache|Thumbs.db";
@img_ext   = ('avi', 'cr2', 'jpg', 'jpeg', 'tiff');
$this_file = basename($0, "");
%thmb      = (
  'ext'    => "jpg",
  'dir'    => "thmb",
);
$sep_sign = '_';
#@raw_ext  = ('cr2', 'dng');
# cr2 - RAW for Canon cameras
# 3fr - RAW for Hasselblad cameras
# sr2 - RAW for Sony cameras
# nef - RAW for Nikon cameras
#@raw_ext  = ('cr2', '3fr', 'sr2', 'nef');
@raw_ext  = ('cr2', 'nef');
$dng_ext  = 'dng';

$shell_var = $^O;
# if OS is unix like this variable has to be true
$unix_like = ($shell_var =~ m/solaris|linux|freeBSD|hp-ux|darwin/) ? 1 : 0;
print STDOUT "\$^O = $^O\n" if(defined($testing));
print STDOUT "\$unix_like = $unix_like\n" if(defined($testing));
print STDOUT "\$shell_var = $shell_var\n" if(defined($testing));

print STDOUT "the shell is " if(defined($testing));

switch ($shell_var) {
    case /darwin/
    {
      $dng_converter = "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter";
      print STDOUT "MacOSX\n" if(defined($testing));
    }
    case /solaris/  { print STDOUT "solaris\n" if(defined($testing)); }
    case /freeBSD/  { print STDOUT "freeBSD\n" if(defined($testing)); }
    case /hp-ux/    { print STDOUT "hp-ux\n"   if(defined($testing)); }
    case /windows/ 
    {
      $dng_converter = 'C:\Program Files\Adobe DNG Converter.exe';
      print STDOUT "windows\n" if(defined($testing));
    }
    else            { print STDOUT "no se\n"   if(defined($testing)) }
}


print STDOUT "\@ARGV  = ", scalar(@ARGV), "\n" if(defined($testing));
print STDOUT "\$ARGV[0] = $ARGV[0]\n" if(defined($ARGV[0]) && defined($testing));
print STDOUT "\$this_file = $this_file\n" if(defined($this_file) && defined($testing));
print STDOUT "\$opt_h = $opt_h\n" if(defined($opt_h) && defined($testing));
print STDOUT "\$opt_d = $opt_d\n" if(defined($opt_d) && defined($testing));


die "\n$this_file - renames and moves image files to a directory manufacturer_model_extension. \
\
usage: $this_file \
-h             - help, this screen \
-d <dir  name> - directory name, default is \".\" \n"
  if(@ARGV!=0 ||
    (defined($opt_h) && $opt_h == 1));


#-------------------------------------------------------------------------------
# Sub functions prototypes
#-------------------------------------------------------------------------------
sub read_dir ( );
sub move_and_rename_files ( $$ );
sub read_raw_dirs ( );
sub convert_to_dng ( $ );
sub process_pids ( $$$ );
sub delete_raw_dirs ( $ );
sub convert_to_dng_task( $$ );


#=============================================================================
# main program
#=============================================================================
# if the directory was not defined
my ($curDir) = (!defined($opt_d) || $opt_d eq '.' || $opt_d eq './') ? '.' : cwd();

print STDOUT "[MAIN] \$curDir = $curDir\n" if(defined($testing));

# change to the directory if required
if($curDir ne '.')
{
  chdir "$opt_d" or die "cannot change to directory $opt_d: $!\n";
  print STDOUT "[MAIN] current directory = $ENV{PWD}\n" if(defined($testing));
}


#--------------------------------------------------------------------------
# read file names in the directory
#--------------------------------------------------------------------------
($hash_ref, $hash_new_names) = read_dir();

#--------------------------------------------------------------------------
# check whether there is something to go through
#--------------------------------------------------------------------------
if(defined($hash_ref))
{
  print STDOUT "[MAIN] \$hash_ref = $hash_ref, \$hash_new_names = $hash_new_names\n" if(defined($testing));
  #------------------------------------------------------------------------
  # create the directories after the manufacturer_model_type
  #-----------------------------------------------------------------------
  move_and_rename_files($hash_ref, $hash_new_names);
  
  # check for dng converter availability
  if(defined($dng_converter) && -f $dng_converter)
  {
    print STDOUT "[MAIN] dng_converter available\n" if(defined($testing));

    # read original directory with RAW files
    $raw_hash = read_raw_dirs ( );
    # convert to dng and if successful delete the original raw directory
    print STDOUT "[MAIN] \$raw_hash = $raw_hash\n" if(defined($testing));
    
    if ( convert_to_dng ( $raw_hash ) )
    {
      delete_raw_dirs ( $raw_hash );
    }
    else
    {
      print STDOUT "[MAIN] convert_to_dng delivered false!\n";
    }

  }
}
else
{
  print STDOUT "[MAIN] Nothing to update: \$dir_content undefined or empty\n";
}

#--------------------------------------------------------------------------
# change back to directory where we were
#--------------------------------------------------------------------------
if($curDir ne '.')
{
  chdir "$curDir" or die "cannot change to directory $curDir: $!\n";
  print STDOUT "current directory = $ENV{PWD}\n" if(defined($testing));
}


################################################################################
# Name :          read_dir
################################################################################
# function:       reads directory content
################################################################################
sub read_dir ( )
{
  my
  (
    @array_tmp,
    $create_date,
    $cur_dir,
    $day,
    $file,
    @file_names,
    @exif_tags,
    $make,
    $model,
    $month,
    %ret_hash,
    %ret_hash_names
  );
  print STDOUT "-> [READ_DIR]\n" if(defined($testing));

  @array_tmp  = ();
  $create_date = 'CreateDate';
  $cur_dir    = basename(cwd());
  @file_names = ();
  $make       = 'Make';
  $model      = 'Model';

  #-----------------------------------------------------------------------------
  # check current directory name
  #-----------------------------------------------------------------------------
  $cur_dir =~ /^\d{4}(\d{2})(\d{2})_\w+$/;
  $month = $1;
  $day   = $2;

  die "wrong month $month\n" if(defined($month) && $month > 12);
  die "wrong day $day\n" if(defined($day) && $day > 31);

  #-----------------------------------------------------------------------------
  # read theme directories
  #-----------------------------------------------------------------------------
  opendir(CUR_DIR, ".") or die "$errors{openDir} $ENV{PWD}: $!\n";
#  @array_tmp = sort grep /^\w+$/, grep -d, readdir CUR_DIR;
#  rewinddir CUR_DIR;
  # sort exclude all files wh . in front of it, read only files
  @file_names = sort grep !/^\./, grep !/$files2exclude/, grep -f, readdir CUR_DIR;
  closedir(CUR_DIR);

  # read the file names and build up a structure
  foreach $file (@file_names)
  {
    my ($dir_name, $file_exif, $file_ext, $file_info, $file_base);
    # get file extension
    lc($file) =~ /\.(\w+)$/;
    $file_base = $`;
    $file_ext  = $1;
    print STDOUT "[READ_DIRS] \$file_base = $file_base, \$file_ext = $file_ext \n" if(defined($testing) && defined($file_ext));

    # check if it is a thumbnail from a raw file
    if($file_ext eq $thmb{'ext'})
    {
      foreach(@raw_ext)
      {
        $file_ext = $thmb{'dir'} if(-f "$file_base.$_")
      }
    }
    $file_exif = new Image::ExifTool;
    $file_exif->Options(DateFormat => '%Y%m%d_%H%M%S');
    
    @array_tmp  = ($make, $model, $create_date);
    $file_info = $file_exif->ImageInfo($file);
    $file_info = $file_exif->GetInfo($file, \@array_tmp);

    print STDOUT "[READ_DIRS] \$file = $file, \$file_ext = $file_ext \n" if(defined($testing) && defined($file_ext));
#    printf("%-24s : %s\n", $make, $$file_info{$make});
#    printf("%-24s : %s\n", $model, $$file_info{$model});
#    printf("%-24s : %s\n", $create_date, $$file_info{$create_date});

    # modify make to just 1 word
    if(defined($$file_info{$make}))
    {
      @array_tmp = split /\s+/, $$file_info{$make};
      $$file_info{$make} = lc(shift @array_tmp);
    }
    else
    {
      $$file_info{$make} = 'unknown';      
    }

    # modify model to just 1 word
    if(defined($$file_info{$model}))
    {
      @array_tmp = split /\s+/, $$file_info{$model};
      # if the make is the same as the first word in the model strip it

      if($$file_info{$make} eq lc($array_tmp[0]))
      {
        shift @array_tmp;
        # strip eos
        if($abk_canon_mod)
        {
          if(defined($array_tmp[1]) && lc($array_tmp[0]) eq 'eos')
          {
            shift @array_tmp;
          }
          if(defined($array_tmp[0]) && lc(join '_', @array_tmp) eq '5d_mark_ii')
          {
            undef(@array_tmp);
            push(@array_tmp, '5dm2');
          }
        }
      }
      $$file_info{$model} = lc(join '', @array_tmp);
      @array_tmp = split /,/, $$file_info{$model};
      $$file_info{$model} = shift @array_tmp;
    }
    else
    {
      $$file_info{$model} = 'unknown';      
    }

    $dir_name = join '_', $$file_info{$make}, $$file_info{$model}, $file_ext;
    
    push @{$ret_hash{$dir_name}}, $file;
    push @{$ret_hash_names{$dir_name}}, $$file_info{$create_date};
  }

#   if(defined($testing))
#   {
#     foreach(keys %ret_hash)
#     {
#       print STDOUT "[READ_DIRS] \$ret_hash{$_} = @{$ret_hash{$_}}\n";
#     }
# 
#     foreach(keys %ret_hash_names)
#     {
#       print STDOUT "[READ_DIRS] \$ret_hash_names{$_} = @{$ret_hash_names{$_}}\n";
#     }
#     
#   }

  print STDOUT "<- [READ_DIR]\n" if(defined($testing));
  return \%ret_hash, \%ret_hash_names;
}


################################################################################
# Name :          move_and_rename_files
################################################################################
# function:       creates directory structure and moves the files
################################################################################
sub move_and_rename_files ( $$ )
{
  my ($dir_hash, $file_hash) = @_;
  my $i;
  my $event_name;
  my @array_tmp;
  my $date_backup;
  my $cam_model;
  print STDOUT "-> [MOVE_AND_RENAME_FILES]\n" if(defined($testing));

  print STDOUT "[MOVE_AND_RENAME_FILES] \$dir_hash = $dir_hash, \$file_hash = $file_hash\n" if(defined($testing));

  # get the last part of directory
  $event_name = lc(basename(cwd()));
  # print STDOUT "1 [MOVE_AND_RENAME_FILES] \$event_name = $event_name\n" if(defined($testing));
  @array_tmp = split $sep_sign, $event_name;
  $date_backup = shift @array_tmp;
  # print STDOUT "2[MOVE_AND_RENAME_FILES] \$date_backup = $date_backup\n" if(defined($testing));
  $event_name = join $sep_sign, @array_tmp;
  # print STDOUT "[MOVE_AND_RENAME_FILES] dir = $event_name\n" if(defined($testing));

  # create sub directory structure
  foreach(keys %{$dir_hash})
  {
    my $file_ext;
    
    lc(${$$dir_hash{$_}}[0]) =~ /\.(\w+)$/;
    $file_ext  = $1;

    mkdir $_, 0755 or die $! unless -d $_;
    print STDOUT "[MOVE_AND_RENAME_FILES] created directory: $_\n";
    for $i (0 .. $#{$$dir_hash{$_}})
    {
      my @dir_array=();
      @dir_array = split($sep_sign, $_);
      $cam_model = $dir_array[1];
#      print STDOUT "[MOVE_AND_RENAME_FILES] \$cam_model = $cam_model\n" if(defined($testing));
    
#      print STDOUT "[MOVE_AND_RENAME_FILES] [$i]old_name: ${$$dir_hash{$_}}[$i]\n" if(defined($testing));
      if(defined(${$$file_hash{$_}}[$i]) && (${$$file_hash{$_}}[$i] ne ""))
      {
        rename ${$$dir_hash{$_}}[$i], sprintf("$_/${$$file_hash{$_}}[$i]_$cam_model" ."_$event_name" . "_" . "%03d.$file_ext", $i+1);
#        print STDOUT sprintf("$_/${$$file_hash{$_}}[$i]_$event_name" . "_" . "%03d.$file_ext\n", $i+1) if(defined($testing));
      }
      else
      {
        rename ${$$dir_hash{$_}}[$i], sprintf("$_/$date_backup" . "_$event_name" . "_" . "%03d.$file_ext", $i+1);
#        print STDOUT sprintf("$_/$date_backup" . "_" . "%03d.$file_ext\n", $i+1) if(defined($testing));
      }
    }
  }
  print STDOUT "<- [MOVE_AND_RENAME_FILES]\n" if(defined($testing));
}

################################################################################
# Name :          read_raw_dirs
################################################################################
# function:       reads directories with RAW files
################################################################################
sub read_raw_dirs ( )
{
  print STDOUT "-> [READ_RAW_DIRS]\n" if(defined($testing));
  my %ret_hash;
  my @array_tmp;
  my $dir;


  opendir(CUR_DIR, ".") or die "$errors{openDir} $ENV{PWD}: $!\n";
  @array_tmp = sort grep /^\w+$/, grep -d, readdir CUR_DIR;
  closedir(CUR_DIR);

  # read the directory names and build up a structure
  foreach $dir (@array_tmp)
  {
    print STDOUT "[READ_RAW_DIRS] \$dir = $dir\n" if(defined($testing));
    foreach(@raw_ext)
    {
      if($dir =~ /$_$/)
      {
        print STDOUT "[READ_RAW_DIRS] \$_ = $_, \$dir = $dir\n" if(defined($testing));

        # read file names of raw files
        opendir(RAW_DIR, "./$dir") or die "$errors{openDir} $ENV{PWD}: $!\n";
        # sort exclude all files with . in front of it
        push @{$ret_hash{$dir}}, sort grep !/^\./, grep !/$files2exclude/, readdir RAW_DIR;
#        @file_names = sort grep !/^\./, grep !/$files2exclude/, grep -f, readdir RAW_DIR;
        closedir(RAW_DIR);
      }
    }
  }
  
  if(defined($testing))
  {
    foreach(keys %ret_hash)
    {
      print STDOUT "[READ_RAW_DIRS] \$ret_hash{$_} = @{$ret_hash{$_}}\n";
    }
  }
  
  print STDOUT "<- [READ_RAW_DIRS]\n" if(defined($testing));
  return \%ret_hash;
}

################################################################################
# Name :          convert_to_dng
################################################################################
# function:       converts proprietary raw files to dng files
#                 returns 1 if all files converted successfully
################################################################################
sub convert_to_dng ( $ )
{
  my ($dng_hash) = @_;
  my ($dng_dir, $raw_dir, $max_kids, %work, @work, %pids, $ret_val, $res);
  
  print STDOUT "-> [CONVERT_TO_DNG] \$dng_hash = $dng_hash\n" if(defined($testing));
  $ret_val = true;
  
  $info = Sys::Info->new;
  $info_cpu  = $info->device( CPU => %options );

  printf STDOUT "[CONVERT_TO_DNG] CPU: %s\n", scalar($info_cpu->identify)  || 'N/A' if(defined($testing));
  printf STDOUT "[CONVERT_TO_DNG] CPU speed is %s MHz\n", $info_cpu->speed || 'N/A' if(defined($testing));
  printf STDOUT "[CONVERT_TO_DNG] There are %d CPUs\n"  , $info_cpu->count || 1 if(defined($testing));
  printf STDOUT "[CONVERT_TO_DNG] Hyper threads %d\n"   , $info_cpu->ht    || 1 if(defined($testing));
  printf STDOUT "[CONVERT_TO_DNG] CPU load: %s\n"       , $info_cpu->load  || 0 if(defined($testing));
  $info_cpu_ht = $info_cpu->ht;

#  print OUTPUT Dumper(%{$raw_ref});

  # if there are more then 1 directory with raw files
  foreach ( keys %{$dng_hash} )
  {
    # replace last 3 characters with dng extension
    $raw_dir = $_;
    $dng_dir = $_;
    $dng_dir =~ s/\w{3}$/$dng_ext/;
    mkdir $dng_dir, 0755 or die $! unless -d $dng_dir;
    printf STDOUT "[CONVERT_TO_DNG] created directory: $dng_dir\n";
    
    # if number of files to convert > then number of available threads
    $max_kids = ( $info_cpu_ht > $#{$$dng_hash{$_}} ) ? $#{$$dng_hash{$_}} + 1 : $info_cpu_ht;
    
    print STDOUT "[CONVERT_TO_DNG] \$max_kids = $max_kids\n" if(defined($testing));
    
    %work = map { $_ => 1 } 1 .. ($#{$$dng_hash{$_}} + 1);
    @work = sort {$a <=> $b} keys %work;

    # loop over number of raw files
    while (@work)
    {
      my $work = shift @work;
      my $pid = undef;

      print STDOUT "[CONVERT_TO_DNG] \$work = $work\n" if(defined($testing));
      print STDOUT "[CONVERT_TO_DNG] \@work = @work\n" if(defined($testing));
      die "[CONVERT_TO_DNG] could not fork" unless defined($pid = fork());

      if ($pid)
      {
        # parent running
        $pids{$pid} = 1;
        print STDOUT "[CONVERT_TO_DNG] $$ parent \$pid = $pid, \$work = $work\n" if(defined($testing));
        # proceed to the next file if there is still a slot available
        # otherwise the loop will wait at the wait condition below
        $res = waitpid $pid, WNOHANG;
        next if (keys %pids < $max_kids and @work);
      }
      else
      {
       # child running
        print STDOUT "[CONVERT_TO_DNG] $$ kid executing $work\n" if(defined($testing));
        if(defined(${$$dng_hash{$_}}[$work-1]) && (${$$dng_hash{$_}}[$work-1] ne ""))
        {
          $ret_val = convert_to_dng_task( $dng_dir, "$raw_dir/${$$dng_hash{$_}}[$work-1]" );
        }
        print STDOUT "[CONVERT_TO_DNG] $$ kid done $work\n" if(defined($testing));
        ($ret_val) ? exit $work : exit 0;
      }
      print "[CONVERT_TO_DNG] $$ waiting\n" if(defined($testing));;
      $res = wait;
#      my $res = waitpid $pid, 0;
#      my $res = waitpid -1, WNOHANG;
      print "[CONVERT_TO_DNG] $$ \$res = $res\n" if(defined($testing));;

      process_pids( \%pids, \%work, $res );
      select undef, undef, undef, .25;
    }
    
    # wait untill all child processes are complete
    while(($res=wait) != -1)
    {
      process_pids( \%pids, \%work, $res );
    }
  }
  print STDOUT "<- [CONVERT_TO_DNG]\n" if(defined($testing));
  return $ret_val;
}

################################################################################
# Name :          process_pids
################################################################################
# function:       processes pids of working kids
################################################################################
sub process_pids ( $$$ )
{
  my ( $pids, $work, $res ) = @_;
  print "-> [PROCESS_PIDS] $pids, $work, $res\n" if(defined($testing));

  if ($res > 0)
  {
    delete $$pids{$res};
    my $rc = $? >> 8; #get the exit status
    print "[PROCESS_PIDS] $$ saw $res was done with $rc\n" if(defined($testing));
    delete $$work{$rc};
    print "[PROCESS_PIDS] $$ work left: ", join(", ", sort {$a <=> $b} keys %{$work}), "\n" if(defined($testing));
  }
  else
  {
    print "[PROCESS_PIDS] $$ wait returned < 0, FAIL\n" if(defined($testing));
  }
  print "<- [PROCESS_PIDS]\n" if(defined($testing));
}

################################################################################
# Name :          delete_raw_dirs
################################################################################
# function:       deletes proprietary raw files
################################################################################
sub delete_raw_dirs ( $ )
{
  my ($dng_hash) = @_;
  my ($dng_dir, $raw_dir) = undef, undef;
  my ($raw_file, $dng_file) = undef, undef;
  my $ret_val = true;
  
  print STDOUT "-> [DELETE_RAW_DIRS]\n" if(defined($testing));

  # check whether all original raw files has been converted
  # if there are more then 1 directory with raw files
  foreach ( keys %{$dng_hash} )
  {
    my @file_names;
    # replace last 3 characters with dng extension
    $raw_dir = $_;
    $dng_dir = $_;
    $dng_dir =~ s/\w{3}$/$dng_ext/;

    print STDOUT "[DELETE_RAW_DIRS] \$dng_dir       = $dng_dir\n" if(defined($testing));
    print STDOUT "[DELETE_RAW_DIRS] \$raw_dir       = $raw_dir\n" if(defined($testing));

    opendir(DNG_DIR, "./$dng_dir") or die "$errors{openDir} $ENV{PWD}: $!\n";
    # sort exclude all files with . in front of it
    push @file_names, sort grep !/^\./, grep !/$files2exclude/, readdir DNG_DIR;
    closedir(DNG_DIR);

    print STDOUT "[DELETE_RAW_DIRS] \$#file_names       = $#file_names\n" if(defined($testing));
    print STDOUT "[DELETE_RAW_DIRS] \$#{$$dng_hash{$_}} = $#{$$dng_hash{$_}}\n" if(defined($testing));
#    print STDOUT "[DELETE_RAW_DIRS] \@file_names = @file_names\n" if(defined($testing));


    if ( $#file_names == $#{$$dng_hash{$_}} )
    {
      for my $i (0 .. $#file_names)
      {
        print STDOUT "[DELETE_RAW_DIRS] \$file_names[$i] = $file_names[$i]\n" if(defined($testing));
        print STDOUT "[DELETE_RAW_DIRS] \${$$dng_hash{$_}}[$i] = ${$$dng_hash{$_}}[$i]\n" if(defined($testing));

        $raw_file = basename(${$$dng_hash{$_}}[$i], @raw_ext);
        $dng_file = basename($file_names[$i], $dng_ext);
        print STDOUT "[DELETE_RAW_DIRS] \$raw_file = $raw_file\n" if(defined($testing));
        print STDOUT "[DELETE_RAW_DIRS] \$dng_file = $dng_file\n" if(defined($testing));

        if($raw_file ne $dng_file)
        {
          $ret_val = false;
          print STDOUT "[DELETE_RAW_DIRS] didn't delete $raw_dir, file names didn't macth\n";
          print STDOUT "[DELETE_RAW_DIRS] \$raw_file != \$dng_file\n" if(defined($testing));
          print STDOUT "[DELETE_RAW_DIRS] $raw_file != $dng_file\n" if(defined($testing));
          last;
        }
      }
    }
    else
    {
      $ret_val = false;
      print STDOUT "[DELETE_RAW_DIRS] didn't delete $raw_dir, number of converted files mismatch\n";
    }
    
    if($ret_val)
    {
      print STDOUT "[DELETE_RAW_DIRS] deleting dir: $raw_dir\n";
      $ret_val = false if (!rmtree($raw_dir, 0, 1));
    }
    else
    {
      print STDOUT "[DELETE_RAW_DIRS] not deleting dir: $raw_dir\n";
    }

  }
  print STDOUT "<- [DELETE_RAW_DIRS]\n" if(defined($testing));
  return $ret_val;
}

################################################################################
# Name :          convert_to_dng_task
################################################################################
# function:       converts proprietary raw files to dng files
################################################################################
sub convert_to_dng_task( $$ )
{
  my ($d_dng, $f_dng) = @_;
  my $ret_val = true;
  my @cmd_param;
  
  print STDOUT "-> [CONVERT_TO_DNG_TASK] $$ \$d_dng = $d_dng, \$f_dng = $f_dng\n" if(defined($testing));

  push @cmd_param, "$dng_converter";
  push @cmd_param, "-c -p1 -n";
  push @cmd_param, "-d";
  push @cmd_param, $d_dng;
  push @cmd_param, $f_dng;
  print STDOUT "[CONVERT_TO_DNG_TASK] $$ @cmd_param\n" if(defined($testing));
  system ( @cmd_param ); 

  if( $? == -1 )
  {
    print STDOUT "[CONVERT_TO_DNG_TASK] $$ dng conversion failed: $!\n" if(defined($testing));
    $ret_val = false;
  }
  else
  {
    printf STDOUT "[CONVERT_TO_DNG_TASK] $$ dng conversion exited with value %d\n", $? >> 8 if(defined($testing));
  }
  print STDOUT "<- [CONVERT_TO_DNG_TASK] $$\n" if(defined($testing));
  return $ret_val;
}

__END__
