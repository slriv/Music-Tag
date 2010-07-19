package Music::Tag::Generic;
use strict;
use warnings;
our $VERSION = 0.36;
use Encode;
use vars qw($AUTOLOAD);
use Carp;
# Copyright (c) 2007,2008,2009,2010 Edward Allen III. Some rights reserved.

#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the README file.
#

=pod

=head1 NAME

Music::Tag::Generic - Parent Class for Music::Tag objects

=head1 SYNOPSIS

    package Music::Tag::SuperMusic;

	use base qw(Music::Tag::Generic);

	sub set_tag {
		my $self = shift;
		$self->info->artist($self->info->artist . " is super");
		return $self->info;
	}

	1;

=head1 DESCRIPTION

Base class.  See L<Music::Tag|Music::Tag>.

=pod

=head1 PLUGINS

All plugins should set @ISA to include Music::Tag::Generic and contain one or more of the following methods:

=over 4

=item B<new()>

Set in template. If you override, it should take as options a reference to a Music::Tag object and an href of options. 

=cut

sub new {
    my $class   = shift;
    my $parent  = shift;
    my $options = shift || {};
    my $self    = {};
    bless $self, $class;
    $self->info($parent);
    $self->options($options);
    return $self;
}

=pod

=item B<info()>

Should return a reference to the associated Music::Tag object. If passed an object, should set the associated Music::Tag object to it.

=cut

sub info {
    my $self = shift;
    my $val  = shift;
    if ( defined $val && ref $val ) {
        $self->{info} = $val;
    }
    return $self->{info};
}

=item B<get_tag()>

Populates the data in the Music::Tag object.

=cut

sub get_tag {
}

=item B<set_tag()>

Optional method to save info.

=cut

sub set_tag {
}

=pod

=item B<strip_tag>

Optional method to remove info. 

=cut

sub strip_tag {
}

=item B<close>

Optional method to close open file handles.

=cut

sub close {
}

=item B<tagchange>

Inherited method that can be called to announce a data-value change from what is read on file. Used by secondary plugins like Amazon, MusicBrainz, and File.  This is preferred to using C<<$self->info->changed(1)>>.

=cut

sub tagchange {
    my $self = shift;
    my $tag  = lc(shift);
    my $to   = shift || $self->info->$tag || "";
    $self->status( $self->info->_tenprint( $tag, 'bold blue', 15 ) . '"' . $to . '"' );
    return $self->info->changed(1);
}

=item B<simplify>

A useful method for simplifying artist names and titles. Takes a string, and returns a sting with no whitespace.  Also removes accents (if Text::Unaccent::PurePerl is available) and converts numbers like 1,2,3 as words to one, two, three... (English is used here.  Let me know if it would be helpful to change this. I do not change words to numbers because I prefer sorting "5 Star" under f).  Removes known articles, such as a, the, an, le les, de if they are not at the end of a string. 

=cut

sub simplify {
    my $self = shift;
    my $text = shift;
    chomp $text;
    return $text unless $text;

    if ( $self->options->{Unaccent} ) {
        $text = Text::Unaccent::PurePerl::unac_string($text);
    }

    $text = lc($text);

    $text =~ s/\[[^\]]+\]//g;
    $text =~ s/[\s_]/ /g;

    if ( length($text) > 5 ) {
        $text =~ s/\bthe\s//g;
        $text =~ s/\ba\s//g;
        $text =~ s/\ban\s//g;
        $text =~ s/\band\s//g;
        $text =~ s/\ble\s//g;
        $text =~ s/\bles\s//g;
        $text =~ s/\bla\s//g;
        $text =~ s/\bde\s//g;
    }
    if ( $self->options->{Inflect} ) {
        $text =~ s/(\.?\d+\,?\d*\.?\d*)/Lingua::EN::Inflect::NUMWORDS($1)/egxms;
    }
    else {
        $text =~ s/\b10\s/ten /g;
        $text =~ s/\b9\s/nine /g;
        $text =~ s/\b8\s/eight /g;
        $text =~ s/\b7\s/seven /g;
        $text =~ s/\b6\s/six /g;
        $text =~ s/\b5\s/five /g;
        $text =~ s/\b4\s/four /g;
        $text =~ s/\b3\s/three /g;
        $text =~ s/\b2\s/two /g;
        $text =~ s/\b1\s/one /g;
    }

    $text =~ s/\sii\b/two/g;
    $text =~ s/\siii\b/three/g;
    $text =~ s/\siv\b/four/g;
    $text =~ s/\sv\b/five/g;
    $text =~ s/\svi\b/six/g;
    $text =~ s/\svii\b/seven/g;
    $text =~ s/\sviii\b/eight/g;

    # Don't translate IX because of a soft spot in my heart for the technologically rich planet.

    $text =~ s/[^a-z0-9]//g;
    return $text;
}

=item B<simple_compare> ($a, $b, $required_percent)

Returns 1 on match, 0 on no match, and -1 on approximate match.   $required_percent is
a value from 0...1 which is the percentage of similarity required for match.  

=cut

sub simple_compare {
    my $self            = shift;
    my $a               = shift;
    my $b               = shift;
    my $similar_percent = shift;
    my $crop_percent    = shift;

    my $sa = $self->simplify($a);
    my $sb = $self->simplify($b);
    if ( $sa eq $sb ) {
        return 1;
    }

    return unless ( $similar_percent || $crop_percent );

    my $la  = length($sa);
    my $lb  = length($sb);
    my $max = ( $la < $lb ) ? $lb : $la;
    my $min = ( $la < $lb ) ? $la : $lb;

    return unless ( $min and $max );

    my $dist = undef;
    if ( $self->options->{LevenshteinXS} ) {
        $dist = Text::LevenshteinXS::distance( $sa, $sb );
    }
    elsif ( $self->options->{Levenshtein} ) {
        $dist = Text::Levenshtein::distance( $sa, $sb );
    }
    unless ($crop_percent) {
        $crop_percent = $similar_percent * ( 2 / 3 );
    }

    if ( ( defined $dist ) && ( ( ( $min - $dist ) / $min ) >= $similar_percent ) ) {
        return -1;
    }

    if ( $min < 10 ) {
        return 0;
    }
    if ( ( ( ( 2 * $min ) - $max ) / $min ) <= $crop_percent ) {
        return 0;
    }
    if ( substr( $sa, 0, $min ) eq substr( $sb, 0, $min ) ) {
        return -1;
    }
    return 0;
}

=item B<status>

Inherited method to print a pretty status message. If first argument is a number, assumes this is required
verbosity. 

=cut

sub status {
    my $self = shift;
    $self->info->status( ref($self), @_ );
	return;
}

=item B<error>

Inherited method to print an error message.

=cut

sub error {
    my $self = shift;
    carp( ref($self), " ", @_ );
	return;
}

=item B<changed>

Same as $self->info->changed().  Please use L<tagchange> method instead.

=cut

sub changed {
    my $self = shift;
    return $self->info->changed(@_);
}

=item B<wav_out()>

If plugin is for a media tag, return stream of wav to filehandle $fh. 

Return True on success, False on failure, undef if not supported.

=cut

sub wav_out {
    my $self = shift;
    my $fh   = shift;
    if ( $self->options->{wav_out_system} ) {
        my @sys = ();
        foreach ( @{ $self->options->{wav_out_system} } ) {
            my $a = $_;
            $a =~ s/\[FILENAME\]/$self->info->filename()/ge;
            push @sys, $a;
        }
        $self->status( 0, "Executing ", join( " ", @sys ) );
		my $in;
        if ( open( $in, '-|', @sys ) ) {
            binmode $in;
            binmode $fh;
            my $buffer = "";
            while ( my $count = sysread( $in, $buffer, 1024 ) ) {
                my $wrote = 0;
                while ( $wrote < $count ) {
                    $wrote += syswrite( $fh, $buffer, ( $count - $wrote ), $wrote );
                }
                $buffer = "";
            }
            return 1;
        }
		CORE::close($in);
        return 0;
    }
    return;
}

=item B<options>

Returns a hashref of options (or sets options, just like Music::Tag method).

=cut

sub options {
    my $self = shift;
    unless ( exists $self->{_options} ) {
        $self->{_options} = Config::Options->new( $self->default_options );
    }
    return $self->{_options}->options(@_);
}

=pod

=item B<default_options>

Method should return default options.

=cut

sub default_options { return {} }

sub DESTROY {
    my $self = shift;
    if ( exists $self->{info} ) {
        delete $self->{info};
    }
	return;
}

1;

=back

=head1 SEE ALSO

L<Music::Tag|Music::Tag>

=head1 AUTHOR 

Edward Allen III <ealleniii _at_ cpan _dot_ org>

=head1 COPYRIGHT

Copyright (c) 2007,2008 Edward Allen III. Some rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
