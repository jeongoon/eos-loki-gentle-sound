# -*- Mode: cperl; cperl-indent-level:4; tab-width: 8; indent-tabs-mode: nil -*-
# -*- coding: utf-8 -*-
# vim: set tabstop 8 expandtab:

# Copyright (c) 2016,2017 JEON Myoungjin <jeongoon@gmail.com>

package FreeDE::ExecDesktopFile;
use parent 'Exporter';
use boolean;
use version 0.77; our $VERSION = version->declare( 'v0.1' );

use FreeDE::App qw(-subLibary app :msg);

our @EXPORT = qw(execDesktopFile);

BEGIN {
    require FreeDE::App;
    FreeDE::App->Exporter::import( qw(app :msg) );
}

sub parseExecArgs_ {
    require Parse::CommandLine;
    Parse::CommandLine->import;

    goto &Parse::CommandLine::parse_command_line;
}

sub execDesktopFile ($;$$) {
    shift if $_[0] eq __PACKAGE__ and not -r __PACKAGE__;
    my ( $file_path, $log_path ) = @_; # $log_path (optional)

    -r $file_path or
      info $@ = "$file_path: $!: ignore this file.",
      return false;

    my $content = app->slurpFile( $file_path, { encoding => 'utf8' } );
    dmsg "File: $file_path: contains:\n$content\n";

    my $exec_line;
    if ( $content =~ m/Exec=(.+)(?:\r\n|[\r\n])/ ) {
        $exec_line = $1;
        dmsg "Exec entry found: $1: try to parse and execute the line";
    }
    else {
        info "Exec entry NOT FOUND: failed to execute a desktop file";
        return false;
    }

    my @parsed_exec_line = parseExecArgs_( $exec_line );
    dmsg "calling exec with: ", join "\n", @parsed_exec_line;

    my $pid = fork;
    if ( not defined $pid ) {
        info "Could not fork: ignore the file: $file_path";
        return false;
    }

    if ( $pid == 0 ) { # child process
        {
            no warnings 'exec';

            defined $log_path
              and dmsg "Log path($log_path) is defined: use to record logs."
              and close STDOUT
              and close STDERR
              and open  STDOUT, ">> $log_path"
              and open  STDERR, ">&    STDOUT";

            exec @parsed_exec_line;
        }
    }
    else { # parent process
        dmsg "fork() succeed.";
        dmsg "child process ID: $pid";
    }

    true;
}

!!'^^';
