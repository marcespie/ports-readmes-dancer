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

my $db = DBI->connect("dbi:SQLite:dbname=".config->{database}, '', '', {});

my $category;
my $list_req = $db->prepare(
	q{select
		distinct(categorykeys.value)
	    from categorykeys
	    order by categorykeys.value
	    });
$list_req->bind_columns(\($category));
$list_req->execute;

my $list_cat_req = $db->prepare(
	q{select paths.fullpkgpath,
		fullpkgname
	    from paths
		join Ports on paths.id=Ports.fullpkgpath 
		join categories on categories.fullpkgpath=paths.id
		join categorykeys on categorykeys.keyref=categories.value
		where categorykeys.value=?
		order by fullpkgname
	    });
my ($fullpkgpath, $fullpkgname);
$list_cat_req->bind_columns(\($fullpkgpath, $fullpkgname));

my $info_req = $db->prepare(
	q{select
		paths.id,
		paths.fullpkgpath,
		p2.fullpkgpath,
		ports.comment,
		ports.homepage,
		descr.value,
		fullpkgname,
		permit_cd.value,
		permit_ftp.value,
		email.value
	    from paths 
	    	join paths p2 on p2.id=paths.pkgpath
		join Ports on paths.id=Ports.fullpkgpath 
		left join Descr on paths.id=Descr.fullpkgpath
		join keywords2 permit_cd 
		    on ports.permit_package_cdrom=permit_cd.keyref
		join keywords2 permit_ftp 
		    on ports.permit_package_ftp=permit_ftp.keyref
		join email on ports.maintainer=email.keyref
	    where paths.fullpkgpath=?});
my ($id, $path, $simplepath, $comment, $homepage, $descr, $permit_cd, $permit_ftp, $maintainer);
$info_req->bind_columns(\($id, $path,  $simplepath, $comment, $homepage, $descr, $fullpkgname, $permit_cd, $permit_ftp, $maintainer));

my $dep_req = $db->prepare(
	q{select 
		depends.type,
		depends.fulldepends,
		t2.fullpkgpath
	from depends 
		join paths on depends.dependspath=paths.id
		join paths t2 on paths.canonical=t2.id
	where depends.fullpkgpath=?
		order by depends.fulldepends
	});
my ($type, $fulldepends, $dependspath);
$dep_req->bind_columns(\($type, $fulldepends, $dependspath));

my $revdep_req = $db->prepare(
	q{select
		distinct(paths.fullpkgpath)
	from paths
		join paths t3 on t3.canonical = paths.id
		join paths t2 on t2.pkgpath=t3.id
		join depends on depends.fullpkgpath=t2.id
		where depends.dependspath in
			(select id from paths where canonical=?)
	order by paths.fullpkgpath});
	    
my $revpath;
$revdep_req->bind_columns(\$revpath);

my $multi_req = $db->prepare(
	q{select
		ports.fullpkgname,
		t2.fullpkgpath
	    from multi 
	    	join paths on multi.subpkgpath=paths.id
		join paths t2 on paths.canonical=t2.id
		join ports on paths.canonical=ports.fullpkgpath
	    where multi.fullpkgpath=?
	    });
my ($multi, $subpath);
$multi_req->bind_columns(\($multi, $subpath));
my $only_for = $db->prepare(
	q{select
		Arch.value
	    from OnlyForArch
	    	join Arch on arch.keyref=OnlyForArch.value
	    where OnlyForArch.fullpkgpath=?
	    order by Arch.value
	});
my $arch;
$only_for->bind_columns(\($arch));
my $not_for = $db->prepare(
	q{select
		Arch.value
	    from NotforArch
	    	join Arch on arch.keyref=NotForArch.value
	    where NotForArch.fullpkgpath=?
	    order by Arch.value
	});
$not_for->bind_columns(\($arch));
my $cat_req = $db->prepare(
	q{select
		categorykeys.value
	    from categories
	    	join categorykeys on categorykeys.keyref=categories.value
	    where categories.fullpkgpath=?
	    order by categorykeys.value
	    });
$cat_req->bind_columns(\($category));

my $broken_req = $db->prepare(
	q{select
		arch.value,
		broken.value
	    from broken
	    	left join arch on arch.keyref=broken.arch
	    where fullpkgpath=?
	    order by arch.value});
	
my $broken;
$broken_req->bind_columns(\($arch, $broken));

my $readme_req = $db->prepare(
	q{select 
		readme.value
	    from readme
	    where fullpkgpath=?});

my $readme;
$readme_req->bind_columns(\$readme);

my $canonical_req = $db->prepare(
	q{select 
		paths.fullpkgpath
	    from paths
	    join paths t2 on t2.canonical=paths.id
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
	unless ($permit_cd =~ /yes/i) {
		$e->{permit_cd} = $permit_cd;
	}
	unless ($permit_ftp =~ /yes/i) {
		$e->{permit_ftp} = $permit_ftp;
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
				if (m/^.*?\:(.*?)\:/) {
					$h{$1} = 1;
				}
			}
			close $fh;
			push(@where, "paths.fullpkgpath in (".join(', ', map {$db->quote($_)} keys %h).")");
		}
	}

	if ($search->{descr}) {
		my $d = "%$search->{descr}%";
		push(@params, $d, $d);
		$s .= q{left join Descr on paths.id=Descr.fullpkgpath};
		push(@where, q{(descr.value like ? or ports.comment like ?)});
	}
	if ($search->{maintainer}) {
		push(@params, "%$search->{maintainer}%");
		$s .= q{
			join email on ports.maintainer=email.keyref
		    };
		push(@where, q{email.value like ?});
	}
	if ($search->{category}) {
		push(@params, $search->{category});
		$s .= q{
		join categories on categories.fullpkgpath=paths.id
		join categorykeys on categorykeys.keyref=categories.value};
		push(@where, q{categorykeys.value like ?});
	}
	if ($search->{pkgname}) {
		push(@params, "%$search->{pkgname}%");
		push(@where, q{fullpkgname like ?});
	}
	if ($search->{path}) {
		push(@params, "%$search->{path}%");
		push(@where, q{paths.fullpkgpath like ?});
	}
	if (@where > 0) {
		$s.= " where ".join(" and ", @where);
	}
	$s = qq{select
		paths.fullpkgpath, fullpkgname
	    from paths
		join Ports on paths.id=Ports.fullpkgpath
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
