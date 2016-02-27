#!/usr/bin/perl -w
##############################################################################
# author:           Alex Berger
# Copyright:        (C) @lex Berger
# function:         this script will rename images in the subdirectories
#                   for my original images
# version:          V0.2 02/26/2016
# changed by:       Alex Berger
###############################################################################

use strict;
#use lib "$ENV{'HOME'}/lx/bin/lib";
use lib "$ENV{'HOME'}/Pictures/bin";
use lib "/usr/bin/lib";
use Image::ExifTool;
use Getopt::Std;
#use Image::Pimage;
use Cwd;
use Cwd 'chdir';
#use Shell;
use vars qw( $opt_h $opt_d $testing );
use File::Copy;
use File::Basename;
use File::Find;
use Switch;
use Sys::Info;
use Sys::Info::Constants qw( :device_cpu );

# ----------- vars just for testing -------------------------------------------
$testing = 1;
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
$abk_canon_mod = 1;
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
@raw_ext  = ('cr2');


$shell_var = $^O;
# if OS is unix like this variable has to be true
$unix_like = ($shell_var =~ m/solaris|linux|freeBSD|hp-ux|darwin/) ? 1 : 0;
print STDOUT "\$^O = $^O\n";
print STDOUT "\$unix_like = $unix_like\n";
print STDOUT "\$shell_var = $shell_var\n";

print STDOUT "the shell is " if(defined($testing));

switch ($shell_var) {
    case /darwin/
    {
      $dng_converter = '/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter';
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

$info = Sys::Info->new;
$info_cpu  = $info->device( CPU => %options );

printf STDOUT "CPU: %s\n", scalar($info_cpu->identify)  || 'N/A' if(defined($testing));
printf STDOUT "CPU speed is %s MHz\n", $info_cpu->speed || 'N/A' if(defined($testing));
printf STDOUT "There are %d CPUs\n"  , $info_cpu->count || 1 if(defined($testing));
printf STDOUT "Hyper threads %d\n"   , $info_cpu->ht    || 1 if(defined($testing));
printf STDOUT "CPU load: %s\n"       , $info_cpu->load  || 0 if(defined($testing));
$info_cpu_ht = $info_cpu->ht;


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
sub read_raw_dir ( );
sub convert_to_dng ( $$ );
sub delete_raw_dir ( $ );

#=============================================================================
# main program
#=============================================================================
# if the directory was not defined
my ($curDir) = (!defined($opt_d) || $opt_d eq '.' || $opt_d eq './') ? '.' : cwd();

print STDOUT "\$curDir = $curDir\n" if(defined($testing));

# change to the directory if required
if($curDir ne '.')
{
  chdir "$opt_d" or die "cannot change to directory $opt_d: $!\n";
  print STDOUT "current directory = $ENV{PWD}\n" if(defined($testing));
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
  #------------------------------------------------------------------------
  # create the directories after the manufacturer_model_type
  #-----------------------------------------------------------------------
  move_and_rename_files($hash_ref, $hash_new_names);
  
  # check for dng converter availability
  if(defined($dng_converter) && -f $dng_converter)
  {
    print STDOUT "dng_converter available\n" if(defined($testing));

    # read original directory with RAW files
#    read_raw_dir ( );
    # convert to dng and if successful delete the original raw directory
#    if(convert_to_dng ( $$ ))
#    {
#      delete_raw_dir ( $ );
#    }
  }
}
else
{
  print STDOUT "Nothing to update: \$dir_content undefined or empty\n";
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
    $cur_dir, $day,
    $file,
    @file_names,
    @exif_tags,
    $make,
    $model,
    $month,
    %ret_hash,
    %ret_hash_names
  );

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
#  print STDOUT "[READ_DIRS] \@array_tmp = @array_tmp\n" if(defined($testing));
#  die "[READ_DIRS] there should be no sub directories - @array_tmp\n" if($#array_tmp != -1);

  # read the file names and build up a structure
  foreach $file (@file_names)
  {
    my ($dir_name, $file_exif, $file_ext, $file_info, $file_base);
    # get file extension
#    lc($file) =~ /^(.+)\.(\w+)$/;
#    $file_base = $1;
#    $file_ext  = $2;
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
#    $file_exif->Options(Unknown => 1, DateFormat => '%Y%m%d_%H%M%S');
    $file_exif->Options(DateFormat => '%Y%m%d_%H%M%S');
    
    @array_tmp  = ($make, $model, $create_date);
#    $file_info = $file_exif->ImageInfo($file, \@array_tmp);
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
#    printf("%-24s : %s\n", $make, $$file_info{$make});

    # modify model to just 1 word
    if(defined($$file_info{$model}))
    {
      @array_tmp = split /\s+/, $$file_info{$model};
      # if the make is the same as the first word in the model strip it
#      printf("Model 1st : %s\n", lc($array_tmp[0]));

      if($$file_info{$make} eq lc($array_tmp[0]))
      {
#        print "1 ", @array_tmp, "\n";
        shift @array_tmp;
#        print "2 ", @array_tmp, "\n";
        # strip eos
        if($abk_canon_mod == 1)
        {
          if(defined($array_tmp[1]) && lc($array_tmp[0]) eq 'eos')
          {
            shift @array_tmp;
#            print "3 ", @array_tmp, "\n";
          }
          if(defined($array_tmp[0]) && lc(join '_', @array_tmp) eq '5d_mark_ii')
          {
            undef(@array_tmp);
            push(@array_tmp, '5dm2');
#            print "4 ", @array_tmp, "\n";
          }
        }
      }
      $$file_info{$model} = lc(join '', @array_tmp);
#      $$file_info{$model} = lc(pop @array_tmp);
      @array_tmp = split /,/, $$file_info{$model};
      $$file_info{$model} = shift @array_tmp;
    }
    else
    {
      $$file_info{$model} = 'unknown';      
    }
#    printf("%-24s : %s\n", $model, $$file_info{$model});

    $dir_name = join '_', $$file_info{$make}, $$file_info{$model}, $file_ext;
    
    push @{$ret_hash{$dir_name}}, $file;
    push @{$ret_hash_names{$dir_name}}, $$file_info{$create_date};
  }

  if(defined($testing))
  {
    foreach(keys %ret_hash)
    {
      print STDOUT "[READ_DIRS] \$ret_hash{$_} = @{$ret_hash{$_}}\n";
    }

    foreach(keys %ret_hash_names)
    {
      print STDOUT "[READ_DIRS] \$ret_hash_names{$_} = @{$ret_hash_names{$_}}\n";
    }
    
  }

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

#  get the last part of directory
  $event_name = lc(basename(cwd()));
#  print STDOUT "1 [CREATE_DIRS] \$event_name = $event_name\n";
  @array_tmp = split $sep_sign, $event_name;
  $date_backup = shift @array_tmp;
#  print STDOUT "2[CREATE_DIRS] \$date_backup = $date_backup\n";
  $event_name = join $sep_sign, @array_tmp;
#  print STDOUT "[CREATE_DIRS] dir = $event_name\n";

  # create sub directory structure
  foreach(keys %{$dir_hash})
  {
    my $file_ext;
    
    lc(${$$dir_hash{$_}}[0]) =~ /\.(\w+)$/;
    $file_ext  = $1;

    mkdir $_, 0755 or die $! unless -d $_;
    print STDOUT "[CREATE_DIRS] created directory name: $_\n";
    for $i (0 .. $#{$$dir_hash{$_}})
    {
      my @dir_array=();
      @dir_array = split($sep_sign, $_);
      $cam_model = $dir_array[1];
#      print STDOUT "[CREATE_DIRS] \$cam_model = $cam_model\n";
    
#      print STDOUT "[CREATE_DIRS] [$i]old_name: ${$$dir_hash{$_}}[$i]\n";
      if(defined(${$$file_hash{$_}}[$i]) && (${$$file_hash{$_}}[$i] ne ""))
      {
        rename ${$$dir_hash{$_}}[$i], sprintf("$_/${$$file_hash{$_}}[$i]_$cam_model" ."_$event_name" . "_" . "%03d.$file_ext", $i+1);
#        print STDOUT sprintf("$_/${$$file_hash{$_}}[$i]_$event_name" . "_" . "%03d.$file_ext\n", $i+1);
      }
      else
      {
        rename ${$$dir_hash{$_}}[$i], sprintf("$_/$date_backup" . "_$event_name" . "_" . "%03d.$file_ext", $i+1);
#        print STDOUT sprintf("$_/$date_backup" . "_" . "%03d.$file_ext\n", $i+1);
      }
    }
  }
}

__END__
