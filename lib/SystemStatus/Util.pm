package SystemStatus::Util;

use strict;
use warnings;

use Exporter 'import';
use JSON::PP qw(encode_json);

our @EXPORT_OK = qw(
  capture_command
  run_powershell
  fmt_num
  json_error
  json_string
);

sub capture_command {
    my (%args) = @_;
    my $capture = $args{capture};
    my @cmd     = @{ $args{cmd} || [] };

    if ($capture) {
        my ($rc, $out) = $capture->(@cmd);
        $rc  = 0     if !defined $rc;
        return ($rc, $out);
    }

    open my $fh, '-|', @cmd or return (1, undef);
    local $/;
    my $out = <$fh>;
    close $fh;

    return (($? >> 8), $out);
}

sub run_powershell {
    my (%args) = @_;
    my $script = $args{script};

    for my $exe ('powershell.exe', 'powershell', 'pwsh') {
        my ($rc, $out) = capture_command(
            capture => $args{capture},
            cmd     => [ $exe, '-NoProfile', '-NonInteractive', '-Command', $script ],
        );
        return $out if defined $out && $rc == 0 && $out =~ /\S/;
    }

    return undef;
}

sub fmt_num {
    my ($n) = @_;
    $n = 0 if !defined $n;
    my $s = sprintf('%.2f', $n);
    $s =~ s/\.?0+$//;
    return length($s) ? $s : '0';
}

sub json_error {
    my ($msg) = @_;
    return encode_json({ error => $msg }) . "\n";
}

sub json_string {
    my ($value) = @_;
    return encode_json($value);
}

1;
