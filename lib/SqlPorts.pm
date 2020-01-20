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
package SqlPorts;
use DBI;
use Dancer ':syntax';
use strict;
use warnings;

my $db = DBI->connect("dbi:SQLite:dbname=".config->{database}, '', '', 
    {ReadOnly => 1});

my $category;
my $list_req = $db->prepare(
	q{select
		distinct(_categorykeys.value)
	    from _categorykeys
	    order by _categorykeys.value
	    });
$list_req->bind_columns(\($category));
$list_req->execute;

my $list_cat_req = $db->prepare(
	q{select min(_paths.fullpkgpath),
		fullpkgname
	    from _paths
		join _Ports on _paths.id=_Ports.fullpkgpath 
		    and _paths.id=_paths.canonical
		join _categories on _categories.fullpkgpath=_paths.id
		join _categorykeys on _categorykeys.keyref=_categories.value
		where _categorykeys.value=?
		group by fullpkgname
		order by fullpkgname
	    });
my ($fullpkgpath, $fullpkgname);
$list_cat_req->bind_columns(\($fullpkgpath, $fullpkgname));

my $info_req = $db->prepare(
	q{select
		_paths.id,
		_paths.fullpkgpath,
		p2.fullpkgpath,
		_ports.comment,
		_ports.homepage,
		_descr.value,
		fullpkgname,
		permit.value,
		_email.value
	    from _paths 
	    	join _paths p2 on p2.id=_paths.pkgpath
		join _Ports on _paths.id=_Ports.fullpkgpath 
		left join _Descr on _paths.id=_Descr.fullpkgpath
		join _keywords2 permit
		    on _ports.permit_package=permit.keyref
		join _email on _ports.maintainer=_email.keyref
	    where _paths.fullpkgpath=?});
my ($id, $path, $simplepath, $comment, $homepage, $descr, $permit, $maintainer);
$info_req->bind_columns(\($id, $path,  $simplepath, $comment, $homepage, $descr, $fullpkgname, $permit, $maintainer));

my $dep_req = $db->prepare(
	q{select 
		_depends.type,
		_depends.fulldepends,
		t2.fullpkgpath
	from _depends 
		join _paths on _depends.dependspath=_paths.id
		join _paths t2 on _paths.canonical=t2.id
	where _depends.fullpkgpath=?
		order by _depends.fulldepends
	});
my ($type, $fulldepends, $dependspath);
$dep_req->bind_columns(\($type, $fulldepends, $dependspath));

my $revdep_req = $db->prepare(
	q{select
		distinct(_paths.fullpkgpath)
	from _paths
		join _paths t3 on t3.canonical = _paths.id
		join _paths t2 on t2.pkgpath=t3.id
		join _depends on _depends.fullpkgpath=t2.id
		where _depends.dependspath in
			(select id from _paths where canonical=?)
	order by _paths.fullpkgpath});
	    
my $revpath;
$revdep_req->bind_columns(\$revpath);

my $multi_req = $db->prepare(
	q{select
		_ports.fullpkgname,
		t2.fullpkgpath
	    from _multi 
	    	join _paths on _multi.subpkgpath=_paths.id
		join _paths t2 on _paths.canonical=t2.id
		join _ports on _paths.canonical=_ports.fullpkgpath
	    where _multi.fullpkgpath=?
	    });
my ($multi, $subpath);
$multi_req->bind_columns(\($multi, $subpath));
my $only_for = $db->prepare(
	q{select
		distinct(_Arch.value)
	    from _OnlyForArch
	    	join _Arch on _arch.keyref=_OnlyForArch.value
	    where _OnlyForArch.fullpkgpath=?
	    order by _Arch.value
	});
my $arch;
$only_for->bind_columns(\($arch));
my $not_for = $db->prepare(
	q{select
		distinct(_Arch.value)
	    from _NotforArch
	    	join _Arch on _arch.keyref=_NotForArch.value
	    where _NotForArch.fullpkgpath=?
	    order by _Arch.value
	});
$not_for->bind_columns(\($arch));
my $cat_req = $db->prepare(
	q{select
		distinct(_categorykeys.value)
	    from _categories
	    	join _categorykeys on _categorykeys.keyref=_categories.value
	    where _categories.fullpkgpath=?
	    order by _categorykeys.value
	    });
$cat_req->bind_columns(\($category));

my $broken_req = $db->prepare(
	q{select
		_arch.value,
		_broken.value
	    from _broken
	    	left join _arch on _arch.keyref=_broken.arch
	    where fullpkgpath=?
	    order by _arch.value});
	
my $broken;
$broken_req->bind_columns(\($arch, $broken));

my $readme_req = $db->prepare(
	q{select 
		value
	    from _readme
	    where fullpkgpath=?});

my $readme;
$readme_req->bind_columns(\$readme);

my $canonical_req = $db->prepare(
	q{select 
		_paths.fullpkgpath
	    from _paths
	    join _paths t2 on t2.canonical=_paths.id
	    where t2.fullpkgpath=?});

my $canonical;
$canonical_req->bind_columns(\$canonical);
	    
my $e;
while ($list_req->fetch) {
	push(@{$e->{categories}}, {
		name => $category,
		url => "cat/$category"
	});
}

sub listing
{
	return $e;
}

sub category
{
	my ($class, $cat) = @_;
	$list_cat_req->execute($cat);
	my $e = { name => $cat };
	while ($list_cat_req->fetch) {
		push(@{$e->{category}}, {
			name => $fullpkgname,
			url => "/path/$fullpkgpath"
		});
	}
	return $e;
}

sub pkgpath
{
	my ($class, $p) = @_;
	my @depends = (qw(libdepends rundepends builddepends testdepends));

	$info_req->execute($p);
	if(!$info_req->fetch) {
		return undef;
	}
	# zap the email part
	$maintainer =~ s/\s+\<.*?\>//g;
	my $e = { path => $path,
		simplepath => $simplepath,
		comment => $comment,
		homepage => $homepage,
		maintainer => $maintainer,
		descr => $descr,
		fullpkgname => $fullpkgname };
	unless ($permit =~ /yes/i) {
		$e->{permit} = $permit;
	}
	$dep_req->execute($id);
	while ($dep_req->fetch) {
		push(@{$e->{$depends[$type]}},
		    {
			depends => $fulldepends,
			url => "/path/$dependspath"
		    });
	}
	$revdep_req->execute($id);
	while ($revdep_req->fetch) {
		push(@{$e->{reversedepends}},
		    {
			depends => $revpath,
			url => "/path/$revpath"
		    });
	}
	if (open(my $fh, "-|", config->{pkglocate}, ":$path:")) {
		while (<$fh>) {
			if (m/^\Q$fullpkgname\E:\Q$path\E:(.*)/) {
				push(@{$e->{files}}, $1);
			}
		}
		close $fh;
	}

	$broken_req->execute($id);
	while ($broken_req->fetch) {
		push (@{$e->{broken}}, 
		    {
			arch => $arch,
			text => $broken
		    });
	}
	$only_for->execute($id);
	while ($only_for->fetch) {
		push (@{$e->{only_for}}, $arch);
	}
	$not_for->execute($id);
	while ($not_for->fetch) {
		push (@{$e->{not_for}}, $arch);
	}
	$multi_req->execute($id);
	while ($multi_req->fetch) {
		push @{$e->{multi}},
		    {
			name => $multi,
			url => "/path/$subpath"
		    };
	}

	$cat_req->execute($id);
	while ($cat_req->fetch) {
		push @{$e->{category}},
		    {
		    	name => $category, 
			url => "/cat/$category"
		    };
	}
	$readme_req->execute($id);
	if ($readme_req->fetch) {
		$e->{readme} = $readme;
	}
	return $e;
}

sub canonical
{
	my ($class, $path) = @_;
	$canonical_req->execute($path);
	if ($canonical_req->fetch) {
		return $canonical;
	} else {
		return undef;
	}
}

sub search
{
	my ($class, $search) = @_;
	my $s = "";
	my @params = ();
	my @where = ();

	if ($search->{file}) {
		my %h;
		if (open(my $fh, "-|", config->{pkglocate}, $search->{file})) {
			while (<$fh>) {
				next unless m/^.*?\:(.*?)\:(.*)/;
				my ($pkgpath, $filepath) = ($1, $2);
				next unless $filepath =~ m/\Q$search->{file}\E/;
				$h{$pkgpath} = 1;
			}
			close $fh;
			push(@where, "_paths.fullpkgpath in (".join(', ', map {$db->quote($_)} keys %h).")");
		}
	}

	if ($search->{descr}) {
		my $d = "%$search->{descr}%";
		push(@params, $d, $d);
		$s .= q{left join _Descr on _paths.id=_Descr.fullpkgpath};
		push(@where, q{(_descr.value like ? or _ports.comment like ?)});
	}
	if ($search->{maintainer}) {
		push(@params, "%$search->{maintainer}%");
		$s .= q{
			join _email on _ports.maintainer=_email.keyref
		    };
		push(@where, q{_email.value like ?});
	}
	if ($search->{category}) {
		push(@params, $search->{category});
		$s .= q{
		join _categories on _categories.fullpkgpath=_paths.id
		join _categorykeys on _categorykeys.keyref=_categories.value};
		push(@where, q{_categorykeys.value like ?});
	}
	if ($search->{pkgname}) {
		push(@params, "%$search->{pkgname}%");
		push(@where, q{fullpkgname like ?});
	}
	if ($search->{path}) {
		push(@params, "%$search->{path}%");
		push(@where, q{_paths.fullpkgpath like ?});
	}
	if (@where > 0) {
		$s.= " where ".join(" and ", @where);
	}
	$s = qq{select
		_paths.fullpkgpath, fullpkgname
	    from _paths
		join _Ports on _paths.canonical=_Ports.fullpkgpath
		$s
		order by fullpkgname
		};
	my $req = $db->prepare($s);
	$req->bind_columns(\($fullpkgpath, $fullpkgname));
	$req->execute(@params);
	my $e = {};
	while ($req->fetch) {
		push(@{$e->{result}}, {
			name => $fullpkgname,
			url => "/path/$fullpkgpath"
		});
	}
	return $e;
}
true;
