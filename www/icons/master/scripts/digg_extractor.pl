#!/usr/bin/perl
#
# Copyright (C) 2007 Peteris Krumins (peter@catonmat.net)
# http://www.catonmat.net  -  good coders code, great reuse
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use warnings;
use strict;

#
# This program was written as a part of "digpicz: digg's missing picture section"
# website generator.
# This website can be viewed here: http://digpicz.com
#
# See http://www.catonmat.net/designing-digg-picture-website for more info.
#

use LWP;
use POSIX;
use XML::Simple;

binmode(STDOUT, ":utf8");

# Each request to Digg API requires an appkey which is a a valid absolute URI
# that identifies the application making the request.
# This constant defines that key.
# Read more: http://apidoc.digg.com/ApplicationKeys
#
use constant DIGG_APPKEY => 'http://digpicz.com';

# This constant defines now many votes a digg post has had to have received
# to be included in the results. Use 0 to include all posts.
#
#use constant VOTE_THRESHOLD => 60;

use constant ITEMS_PER_REQUEST => 15;

# These regex patterns match common picture titles on Digg.
# It's an array to maintain the order of plural regexes vs. singular regexes.
#
my @extract_patterns = (
    # pattern                  type
    "[[(].*pictures.*[])]" => 'pictures',
    "[[(].*picture.*[])]"  => 'picture',
    "[[(].*pics.*[])]"     => 'pictures',
    "[[(].*pic.*[])]"      => 'picture',
    "[[(].*images.*[])]"   => 'pictures',
    "[[(].*image.*[])]"    => 'picture',
    "[[(].*photos.*[])]"   => 'pictures',
    "[[(].*photo.*[])]"    => 'picture',
    "[[(].*comics.*[])]"   => 'pictures',
    "[[(].*comic.*[])]"    => 'picture',
    "[[(].*charts.*[])]"   => 'pictures',
    "[[(].*chart.*[])]"    => 'picture',
);

# These regex patterns match domains which usually contain only images
# and videos.
my @extract_domains = (
    'photobucket.com'       => 'picture',
    'photo.livevideo.com'   => 'picture',
    'flickr.com'            => 'picture',
    'xkcd.com'              => 'picture'
);

my $ua = LWP::UserAgent->new(
    agent => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US) Gecko/20070515 Firefox/2.0.0.4'
);

my $reqs_to_get = shift || 'all'; # number of requests to get (ITEMS_PER_REQUEST per request)

my $xml_posts = get_posts($ua, 1);
my $posts = parse_posts($xml_posts);

extract_and_print($posts->{story});
$reqs_to_get-- if $reqs_to_get =~ /\d+/;

my $offset = 2;
if ($reqs_to_get eq 'all') {
    do {
        $xml_posts = get_posts($ua, $offset++);
        $posts = parse_posts($xml_posts);
        extract_and_print($posts->{story});
    } while (exists $posts->{story} and @{$posts->{story}});
}
else {
    while ($reqs_to_get--) {
        # note: it doesn't matter that we duplicate code, this program is so small
        # that i typed it in matter of minutes
        $xml_posts = get_posts($ua, $offset++);
        $posts = parse_posts($xml_posts);
        extract_and_print($posts->{story});

        exit 0 unless exists $posts->{story} and @{$posts->{story}};
    }
}

#
# extract_and_print
#
# Given a hashref data structure of posts, find posts matching @extract_patterns and
# @extract_domains and prints them out
#
sub extract_and_print {
    my $posts = shift;

    my @to_print;
    POST:
    foreach my $post (@$posts) { # naive algorithm, we don't care about complexity
        foreach my $idx (grep { $_ % 2 == 0 } 0..$#extract_patterns) {
            # foreach extract pattern
            if ($post->{title} =~ /$extract_patterns[$idx]/i ||
                $post->{description} =~ /$extract_patterns[$idx]/i)
            {
                push @to_print, {
                    entry => $post,
                    type  => $extract_patterns[$idx+1]
                };
                next POST;
            }
        }
        foreach my $idx (grep { $_ % 2 == 0 } 0..$#extract_domains) {
            my $uri = URI->new($post->{link});
            my $host;
            next unless $uri->can('host');
            $host = $uri->host;
            if ($host =~ /$extract_domains[$idx]/i) {
                push @to_print, {
                    entry => $post,
                    type  => $extract_domains[$idx+1]
                };
                next POST;
            }
        }
    }

    print_entries(\@to_print);
}

#
# print_entries
#
# Given a arrayref of entries, prints one by one in our desired format.
# The format is:
#  title: story title
#  type: story type
#  desc: story description
#  url: story url
#  digg_url: url to original story on digg
#  category: digg category of the story
#  short_category: short cateogry name
#  user: username
#  user_pic: url to user pic
#  date: date story appeared on digg YYYY-MM-DD HH::MM::SS
#  <new line>
#
sub print_entries {
    my $entries = shift;
    foreach (@$entries) {
        print "title: $_->{entry}->{title}\n";
        print "type: $_->{type}\n";
        print "desc: $_->{entry}->{description}\n";
        print "url: $_->{entry}->{link}\n";
        print "digg_url: $_->{entry}->{href}\n";
        print "category: $_->{entry}->{topic}->{name}\n";
        print "short_category: $_->{entry}->{topic}->{short_name}\n";
        print "user: $_->{entry}->{user}->{name}\n";
        print "user_pic: $_->{entry}->{user}->{icon}\n";
        print "date: " . strftime("%Y-%m-%d %H:%M:%S", localtime $_->{entry}->{promote_date}) . "\n";
        print "\n";
    }
}

#
# parse_posts
#
# Given XML posts, returns a hashref data structure with them
#
sub parse_posts {
    my $xml = shift;
    return XMLin($xml, KeyAttr => [], ForceArray => ['story']);
}

#
# get_posts
#
# Gets front page ITEMS_PER_REQUEST posts at (offset - 1) * ITEMS_PER_REQUEST
#
sub get_posts {
    my ($ua, $offset) = @_;

    my $service_url = "http://services.digg.com/stories/popular";
    $service_url   .= "?appkey=" . DIGG_APPKEY;
    $service_url   .= "&offset=" . ($offset - 1) * ITEMS_PER_REQUEST;
    $service_url   .= "&count="  . ITEMS_PER_REQUEST;

    return get_page($ua, $service_url);
}

#
# get_page
#
# Given an URL, the subroutine returns content of the resource located at URL.
# die()s if getting the URL fails
#
sub get_page {
    my ($ua, $url) = @_;

    my $response = $ua->get($url);
    unless ($response->is_success) {
        die "Failed getting $url: ", $response->status_line;
    }

    return $response->content;
}

