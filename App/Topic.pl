#service

use strict;
use Digest::SHA qw(sha1 sha1_hex sha1_base64);
use Digest::MD5 qw(md5_hex);
use DBI;
use POSIX qw(ceil);
use List::Util qw(min max);
use DateTime;

sub getSortedTopicsForHomePage{
    my $self = shift;
    my $from = shift;
    my $limit = shift;
    
    if(not defined $from){
        $from = 0;
    }
    if(not defined $limit){
        $limit = 10;
    }
    
    my $stmt = $self->dbh->prepare("
    SELECT t.id as topic_id, t.title as topic_title, thread_id, username as user, thread_title, date_modified, t.date_created as date_created
    FROM topics t left outer join 
    (
        select td.topic_id as topic_id, td.id as thread_id, td.title as thread_title,
        u.username as username, pp.date_created as date_modified
        from threads td, users u, posts pp
        where  pp.thread_id = td.id AND pp.creator_id = u.id 
        order by date_modified DESC
        LIMIT 0, 1
    ) p
    ON p.topic_id = t.id
    ORDER BY date_modified DESC, date_created DESC
    LIMIT $from, $limit
    ") or die $self->dbh->errstr;
    $stmt->execute();
    
    my @rows = ();
    push @rows, $_ while $_ = $stmt->fetchrow_hashref();
    foreach my $ref(@rows){
        my $total_thread = $self->dbh->selectrow_array("SELECT COUNT(*) as total_thread FROM threads td
                                    WHERE td.topic_id = ".$ref->{'topic_id'});
        my $total_post = $self->dbh->selectrow_array("SELECT COUNT(*) as total_post FROM posts p, threads td
                                    WHERE td.topic_id = ".$ref->{'topic_id'}." and td.id = p.thread_id");
        $ref->{'total_thread'} = $total_thread;
        $ref->{'total_post'} = $total_post;
    }
    return @rows;
}
#home_page
sub home_rm{
    my $self = shift;
    
    my $page = $self->query->param('page');
    if(not defined $page){
        $page = 1;
    }
    $page -= 1; #start with zero based page
    
    my $tmpl = $self->load_tmpl('membership/home.tmpl',  die_on_bad_params => 0);
    
    $self->passCredential_Session($tmpl);
    
    $tmpl->param(
        breadcrumbs => [
            { name => "Home", link=>"./index.pl?rm=home", active=>"true"},
        ]
    );
    
    #BEGIN PAGINATION HANDLING
    my $total_topic = $self->dbh->selectrow_array("SELECT COUNT(*) FROM topics");
    my $limit = $self->param('topics_per_page');
    my $total_pages = max(ceil($total_topic/$limit), 1);
    my $limit_pagination = $self->param('page_per_pagination');
    
    
    if(($page+1) > $total_pages){
        die "error params";
    }
    my $start_page = ceil(($page+1)/$limit_pagination);
    my $end_page = min($start_page + $limit_pagination - 1, $total_pages);
    
    
    my @pages = ();
    foreach my $ind(($start_page-1)..($end_page+1)){
        my %hash = {};
        if($ind == ($start_page-1)){
            if($ind <= 0){
                $hash{'disabled'} = "true";                
                
            }else{
                $hash{'not_both'} = "true";
                $hash{'link'} = "./index.pl?rm=home&page=".$ind;   
            }
            $hash{'page'} = "«";
            
        }elsif($ind == ($end_page+1)){
            if($ind > $total_pages){
                $hash{'disabled'} = "true";
            }else{
                $hash{'not_both'} = "true";                
                $hash{'link'} = "./index.pl?rm=home&page=".$ind;
            }
            $hash{'page'} = "»";
        }else{
            if($ind == ($page+1)){
                $hash{'active'} = "true";
            }else{
                $hash{'not_both'} = "true";
            }
            $hash{'link'} = "./index.pl?rm=home&page=".$ind;
            $hash{'page'} = $ind;
        }
        push @pages, \%hash;
    }
    
    #END PAGINATION HANDLING
    my @rows = $self->getSortedTopicsForHomePage($page*$limit, $limit);
    $tmpl->param(topics => \@rows);
    $tmpl->param(pages => \@pages);
    
    return $tmpl->output();
}

#create topic
sub create_topic_rm{
    my $self = shift;
    my $tmpl = $self->load_tmpl('post/create_topic.tmpl', die_on_bad_params => 0);
    if($self->session->param('role') eq 'a'){
        $self->passCredential_Session($tmpl);
        return $tmpl->output();
    }else{
        $self->redirect("./index.pl?rm=home");   
    }
}

#create topic (data POST)
sub create_topic_post_rm{
    my $self = shift;
    my $title = $self->query->param('title');
    my $dateTime = &toDateTime;
    my $status = undef;
    #just admin can create new topic
    if($title && $self->session->param('role') eq 'a'){
        my $stmt = $self->dbh->prepare("INSERT INTO topics(title, date_created, creator_id) VALUES (?,?,?)")
                    or die $self->dbh->errstr;
        $status = $stmt->execute($title, $dateTime, $self->session->param('uid'));
        $self->dbh->commit();
    }
    if($status){
        my $topicId = $self->dbh->selectrow_array("SELECT last_insert_id()");;
        
        $self->redirect("./index.pl?rm=view_topic&topic_id=$topicId");
    }else{
        die $status;
    }
}

#view topic
sub view_topic_rm{
    my $self = shift;
    my $tmpl = $self->load_tmpl('post/view_topic.tmpl',  die_on_bad_params => 0);
    my $topicId = $self->query->param('topic_id');
    my $page = $self->query->param('page');
    if(not defined $page){
        $page = 1;
    }
    
    $page -=1;
    
    if(not defined $topicId){
        $self->redirect("./index.pl?rm=home");
        return;
    }
    
    my $topicTitle = $self->dbh->selectrow_array("SELECT title FROM topics WHERE id = ?", {}, ($topicId));
    
    #BEGIN PAGINATION HANDLING
    my $total_thread = $self->dbh->selectrow_array("SELECT COUNT(*) FROM threads WHERE topic_id = $topicId");
    my $limit = $self->param('threads_per_page');
    my $total_pages = max(ceil($total_thread/$limit), 1); #case for 0 thread, then just 1 pagination
    my $limit_pagination = $self->param('page_per_pagination');
    
    
    if(($page+1) > $total_pages){
        die "error params";
    }
    my $start_page = ceil(($page+1)/$limit_pagination);
    my $end_page = min($start_page + $limit_pagination - 1, $total_pages);
    
    
    my @pages = ();
    foreach my $ind(($start_page-1)..($end_page+1)){
        my %hash = {};
        if($ind == ($start_page-1)){
            if($ind <= 0){
                $hash{'disabled'} = "true";                
                
            }else{
                $hash{'not_both'} = "true";
                $hash{'link'} = "./index.pl?rm=view_topic&topic_id=$topicId&page=".$ind;
            }
            $hash{'page'} = "«";
            
        }elsif($ind == ($end_page+1)){
            if($ind > $total_pages){
                $hash{'disabled'} = "true";
            }else{
                $hash{'not_both'} = "true";                
                $hash{'link'} = "./index.pl?rm=view_topic&topic_id=$topicId&page=".$ind;
            }
            $hash{'page'} = "»";
        }else{
            if($ind == ($page+1)){
                $hash{'active'} = "true";
            }else{
                $hash{'not_both'} = "true";
            }
            $hash{'link'} = "./index.pl?rm=view_topic&topic_id=$topicId&page=".$ind;
            $hash{'page'} = $ind;
        }
        push @pages, \%hash;
    }
    
    #END PAGINATION HANDLING
    
    $self->passCredential_Session($tmpl);
    $tmpl->param('topic_id', $topicId);
    $tmpl->param(pages => \@pages);
    $tmpl->param(
        breadcrumbs => [
            { name => "Home", link=>"./index.pl?rm=home"},
            { name => $topicTitle, active => "true"},
        ]
    );
    my @rows = $self->getSortedThreadsByTopicId($topicId, $page*$limit,$limit);
    $tmpl->param(threads => \@rows);
    return $tmpl->output();
}

1;

