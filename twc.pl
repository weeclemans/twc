#!/usr/bin/perl -w

//
//  twc.pl
//  Transparency Watch Conf
//
//  Created by Vladimir Laskov on 27/07/07.
//  Copyright © 2007 Vladimir Laskov. All rights reserved.
//


use warnings;
use diagnostics;
use strict;
use POSIX;
use IO::Handle;
use IPC::Open2;
use Cwd qw(abs_path); # convert path with symlink to absolute path
use Fcntl qw(:flock :DEFAULT);

# задаем переменные
#$| = 0;
my $daemon_mode = "on"; # on/off daemon mode
my $lock_set = "on"; # on/off lock repeat_start
my $workpath_set = "/usr/local/libexec/audit_pipe";
my $filelist_set = "filelist.conf";
my $commit_log_set = "/usr/local/libexec/audit_pipe/commit.log";
my $pidfile_set = "/usr/local/libexec/audit_pipe/audit_pipe.pid";
my $cfg_glob_lock;
my $zombie_lock_flag;
my $lock_pid;
my $pid;

my $number = 0;
my $date_set;
my $ipaddres_set;
my $username_set;
my $path_set;
my $pipe_log;
my $file_line;
my $dir_set;
my $temp_data;
my $line = "";
my $line_buf;
#my $line2 = "";
my @data_line;
my @commit_out;
my $tmp_volume = 0;

#включаем режим даемона
#daemon_mode();

# отключаем буферизацию
#use IO::Handle; $pipe_read->autoflush(1);
#$|=1;
if ($lock_set eq "on") {

    # ПРОЦЕДУРА предотвращения повторного запуска скрипта
    $cfg_glob_lock = $pidfile_set;

    # Проверяем lock.
    if (-f $cfg_glob_lock){
        # Lock присутствует. Проверяем не дохлый ли процесс.
        my $lock_pid = 0;
        open(LOCK,"<$cfg_glob_lock");
        # Если удалось заблокировать, значит процесс мертв.
        my $zombie_lock_flag = flock(LOCK,  LOCK_EX|LOCK_NB);
        $lock_pid = <LOCK>;
        close (LOCK);
        chomp ($lock_pid);

        if ($lock_pid > 0 && $zombie_lock_flag == 0){
            # Реакция на зависший процесс.
            die "Proccess locked (pid=$lock_pid)";
        } else {
            # Лок от мертвого процесса.
            unlink("$cfg_glob_lock");
            warn("DeadLock detected ($lock_pid)$!\n");
        }
    }
}

if ($daemon_mode eq "on") {
    #включаем режим даемона
    daemon_mode();
}

if ($lock_set eq "on") {
    # Записываем pid в новый lock-файл.
    sysopen(PID, $cfg_glob_lock, O_CREAT|O_EXCL|O_WRONLY) or die "Can not create pid file: $!\n";
        print PID "$$\n";
    close(PID);

    # Открываем lock.
    open(GLOB_LOCK,"<$cfg_glob_lock");
        flock(GLOB_LOCK,  LOCK_EX);

} else {
    open(PID,"> $pidfile_set") || die  "Can not create pid file: $!\n";
        print PID getpid();
    close(PID);
}

# BASIC PART OF CODE
open(PIPE_LOG, "/dev/auditpipe") || die;

    $pid = open2( my $pipe_read, my $pipe_write, "praudit", "-lp");

    while (1) {
        sysread PIPE_LOG, $pipe_log, 65536;
        $number++; # cycle_counter

        print $pipe_write "$pipe_log"; # && close ($pipe_write) or die "Error writing to pipe_write: $!\n";

        #if ( $pipe_log =~ /\// || $pipe_log =~ /flags/ ) {

        sysread $pipe_read, $line_buf, 65536;

#print "stage1 ".$number."\n $line_buf \n";
        my @data_string = split /\n/ => $line_buf;
        my $quantity_strings = scalar(@data_string);

        foreach $line (@data_string) {
            if (($line =~ /- write,creat,0/) || ($line =~ /- write,creat,trunc,0/)) {
                @data_line = split /,/ => $line; # распределяем строку $line в массив


                if ($line =~ /- write,creat,0/) {
                    $date_set = $data_line[6];
                    $ipaddres_set = $data_line[34];
                    $username_set = $data_line[26];
                    $path_set = $data_line[17];
                } else {
                    $date_set = $data_line[7];
                    $ipaddres_set = $data_line[35];
                    $username_set = $data_line[27];
                    $path_set = $data_line[18];
                }

                # проверка по списку файлов
                open (FILE_LIST, "$workpath_set/$filelist_set");
                        while (defined ($file_line = <FILE_LIST>)) {
                            chomp ($file_line);
                            if (Cwd::abs_path($path_set) eq Cwd::abs_path($file_line)) { # сверяем пути к файлам
                                $dir_set = $path_set;
                                $dir_set =~ s/\/[A-Z.a-z]+$//;

                                #@commit_out = readpipe("svn commit --force-log --file /dev/null $file_line");

                                # коммиттим изменения
                                unless (@commit_out = readpipe("cd $dir_set && svn commit -m 'committer $username_set'")) {
                                    open (FILE_LOG,">> $commit_log_set") || die "cannot append: $!";
                                        #select (FILE_LOG);
                                        print FILE_LOG "$date_set not committed: $! \n";
                                    close (FILE_LOG);
                                }

                                $temp_data = scalar(@commit_out); # проверка выполнения коммита

                                if ($temp_data != 0) {
                                    chomp ($commit_out[2]);
                                    $commit_out[2] =~ tr/./ /;

                                    # пишем данные в файл
                                    open (FILE_LOG,">> $commit_log_set") || die "cannot append: $!";
                                    #select (FILE_LOG);
                                        print FILE_LOG "$date_set $ipaddres_set $username_set $path_set $commit_out[2] done \n";
                                    close (FILE_LOG);
                                }
                            }
                        }

                close (FILE_LIST) || die "$!";

            }
        }
    }

# close (FID) || die "$!";

close ($pipe_write);
close ($pipe_read);
#close WRITE_PIPE;
#close READ_PIPE;
waitpid($pid, 0);
close(PIPE_LOG);

if ($lock_set eq "on") {
    # кусок кода процедуры предотвращающей повторный запуск скрипта
    # Закрываем и удаляем lock
    flock(GLOB_LOCK, LOCK_UN);
    close(GLOB_LOCK);
    unlink("$cfg_glob_lock");
}

sub daemon_mode {

    #включаем режим даемона
    if (fork()) {
        exit;
    }

    # пишем pid процесса
#    open(PID,"> $pidfile_set")|| die  "Can not create pid file: $!\n";
#    print PID getpid(); #. "\n";
#    close(PID);

    # отключаем основные дискрипторы
#    close(STDIN);
#    close(STDOUT);
     close(STDERR);
}

