# Copyright (c) 2013 Marc Espie <espie@openbsd.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
package PortsReadmes;
use Dancer2;
use SqlPorts;
use strict;
use warnings;

our $VERSION = '0.1';

sub make_title
{
	my $e = shift;
	$e->{title} = join(": ", "OpenBSD Ports Readme", @_);
}


get '/' => sub {
    my $e = SqlPorts->listing;
    make_title($e);
    $e->{home} = 1;
    template 'index', $e;
};

get '/packages' => sub {
    my $search;
    $search->{name} = '.';
    my $e = SqlPorts->full_list;
    template 'packages', $e;
};

get qr{/cat/([\w\-\/\.\+]+)} => sub {
	my ($cat) = splat;
	my $e = SqlPorts->category($cat);
	make_title($e, "category $cat");

	template 'category', $e;
};

get qr{/path/([\w\-\/\.\+,]+)} => sub {
	my ($p) = splat;
	my $e = SqlPorts->pkgpath($p);
	if (defined $e) {
		make_title($e, "port $p");
		template 'port', $e;
	} else {
		my $p2 = SqlPorts->canonical($p);
		if (defined $p2) {
			redirect("/path/$p2");
		} else {
			forward("404.html");
		}
	}
};

get '/search' => sub {
    my $search;
    if (param "descr") {
    	$search->{descr} = param "descr";
    }
    if (param "pkgname") {
    	$search->{pkgname} = param "pkgname";
    }
    if (param "category") {
    	$search->{category} = param "category";
    }
    if (param "path") {
    	$search->{path} = param "path";
    }
    if (param "file") {
    	$search->{file} = param "file";
    }
    if (param "maintainer") {
    	$search->{maintainer} = param "maintainer";
    }
    my $e = SqlPorts->search($search);
    template 'searchresult', $e;
};
true;
