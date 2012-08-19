package Cache::Memcached::Queue;
use Moose;
use Carp qw/confess cluck/;
use feature qw/say switch/;
use Cache::Memcached::Fast;
use Data::Dumper;
use Data::UUID::MT;

has config_file => ( is => 'rw' );

has memcached   => ( is => 'rw' );

has 'last'      => ( is => 'rw' );

has first       => ( is => 'rw' );

has memcached_servers => (
    is  => 'rw',
    isa => 'Cache::Memcached'
);
has name => ( is => 'rw' );

has id => (
    is       => 'rw',
    required => 'id'
);

has id_prefix => (
    is      => 'rw',
    default => 'CMQID_'
);

has max_enq => (
    is      => 'rw',
    default => 0,
);

has servers => ( is => 'rw', );

has size    => ( is => 'rw' );


=head1 NAME

Cache::Memcached::Queue - Very simple way to create multiple queues and save them on Memcached

=head1 VERSION

Version 0.0.6

alpha version

=cut

BEGIN {
our $VERSION = '0.0.6';
}

=head1 DESCRIPTION

This works by taking advantage of Memcached infrastructure. In other words, the 'keys' 
will be strings that are names of indexes for some basic values that are sufficient to
represent a queue structure. This basic values are: first, last, size and max_enq. 

In order to have multiple queues in the same Memcached server, a prefix are added 
to every index on keys of Memcached. So, every key in memcached have the following 
struct on his name: <PREFIX>_<ID>_<INDEX_NUMBER OR NAME>

=over

=item
PREFIX - This is defined by the 'id_prefix' attribute. The default value is 'CMQID_'

=item
ID - This is defined by the 'id' attribute. If the 'id' attribute was not defined, a UUID
will be defined for it automatically.

=item
INDEX_NUMBER OR NAME - If some data is a item in the queue, so this must be a sequential number,
for example: 'CMQID_1_1' This can be the first element from queue with id 1.
If some data in the queue is a pointer, this pointer must be named, 
for example: 'CMQID_1_first' This is the pointer to the first element in queue.


=back



=head1 SYNOPSIS

This module implements a simple scheme of a Queue.


    use Cache::Memcached::Queue;

    my $q = Cache::Memcached::Queue->new( name => 'foo', 
						max_enq => 10, 
						servers => [{address => '127.0.0.1:11211'}, #other Cache::Memcached::Fast options here... ], 
					  	id => 1,
                        id_prefix => 'MYQUEUE',
					)->init;

    			
    #ENQUEUE
    #do this
    $q->enq({value => $somevalue});

    #DEQUEUE
    my $queue_first_value = $q->deq();

    #WHAT'S THE SIZE OF MY QUEUE ?
    my $size = $q->size();

    #CLEANUP
    $q->cleanup(); #removes everything from object and from Memcached


	
=head2 init()

Initialize object attributes and check attributes problems. If all is ok, returns the reference to object.
Otherwise returns undef and trows an exception

=cut


sub init {
    my ( $self, ) = @_;
    $self->memcached( Cache::Memcached::Fast->new( {servers => $self->servers }) )
                                    or confess "Can't load from memcached! $@";
    if(!defined($self->id) || !$self->id){
       my $uuid_obj = Data::UUID::MT->new();
       $self->id( $uuid_obj->create_string() );
    }
    if(!$self->load()){ #se a lista nao existir, criar
        say "The queue with id '" . $self->id . "' doesn't exist yet. It will be created right now!";
        my $id = $self->id;
        my $real_id = $self->id_prefix . "$id\_";
        my($first,$last,$size) = ($real_id .'1',$real_id.'1',$real_id.'size');
        $self->first($first);
        $self->last($last);
        $self->size(0);
        if(!$self->save(['name','first','last','size', 
                     ])) {
            confess "Sorry, but was not possible to create the Queue - $@";
        }
        else {
            say "The queue '". $self->id_prefix . $self->id ."' was created!";
        }
    }
    else {
        say "The queue '". $self->id_prefix . $self->id ."' is loaded!";
    }
    return $self;
    }



=head2 load()

Try to load the queue pointers from Memcached. If works, will return true. Otherwise 
will return false.

=cut

sub load {
    my ( $self ) = @_;
    my ( $ok, $id ) = ( 0, $self->id );
    
    if( !defined($id) || !$id ){
        confess "Can't load without the id!";    
    }
    else {
        my $real_id = $self->id_prefix . "$id\_";
        my($first,$last,$size,$name) = ($real_id .'first',$real_id.'last',$real_id.'size',$real_id.'name');
        
        #This queue already exists?
        my $real_first = $self->memcached->get($first);
        if(defined($real_first)){

            $self->first($self->memcached->get($first));
            $self->last($self->memcached->get($last));
            $self->size($self->memcached->get($size));
            $self->name($self->memcached->get($name)) if !defined($self->name);
            $ok = 1;
        }
    }
    return $ok;
}



=head2 enq($parameters)

Try to make a 'enqueue' operation. That means tha 'last' index pointer will be readjusted
to the next index. So the value can be recorded on Memcached.

The parameters are validated, and the valid parameters are:

=over

=item
value - A value that presupposes that you want to save

=item
serialize - If you need the value to be serialized, you must set serialized
    to true(1). NOT IMPLEMENTED YET.

=back

Example: $enq({value => 'some_value'});

Example2: $enq({value => $some_object_or_structure,
                serialize => 1, });


If this work, the method will return true. Otherwise, will return false.


=cut

sub enq {
    my ( $self, $parameters ) = @_;
    my ( $ok, $expire, ) = ( 0, undef, undef );
    #validando parametros

    $self->load();
    my $size = $self->size;
    if($size > 0){
        $size += 1;
    }   
    if(defined($self->max_enq) && $self->max_enq >0 && $size > $self->max_enq ){
        say "The queue '".$self->id_prefix."' is full!";
    }
    else {

        my $last = $1 if $self->last =~ /(\d+)$/;
        if($size > 1){
            $last += 1;
        }
        $self->last($self->id_prefix . $self->id . '_' . $last);
        $self->memcached->set($self->last,$parameters->{value},
                                              $parameters->{expire});

        my $size = $self->size;
        $size += 1;
        $self->size($size); 
        $self->save(['last','size']);
    }
    return $ok;
}

=head2 deq()

Try to make a 'dequeue' operation on Queue. That means the first value
of queue will be removed from queue, and the first index pointer from queue will
be moved to the next index. If works, returns the 'dequeued' 
value, otherwise returns undef.

=cut

sub deq {
    my ( $self, ) = @_;
    my ($last_item,$ok) = (undef,undef);
    $self->load;
    my $first_index = $self->first;
    my $value = $self->memcached->get($first_index);
    if(!defined($self->size) || $self->size == 0 ){
        say "Can't deque because the queue '".$self->id_prefix."' is empty!";
    }
    elsif(!$self->memcached->delete($first_index) ){
            say "Sorry, but was not possible to dequeue!";
    }
    else {
        my $index_from_first = $1 if $self->first =~ /(\d+)$/;
        $index_from_first += 1 if $self->size > 1;
        #mounting the new first index.
        my $new_first_index = $self->id_prefix . $self->id . '_' . $index_from_first;
        my $size = $self->size;
        $size -= 1;

        $self->size($size);
        if($size == 0){
            $new_first_index = $self->id_prefix . $self->id . '_1';
            $self->last($new_first_index);
        }
        $self->first($new_first_index);
        $self->save(['first','size','last']);
        $ok = $value;
    }
    return $ok;
}


=head2 show()

Try to show the content of queue(the data). This is made finding the 'first' 
and 'last' pointers, extracting the sequential index, and interate the queue 
with this indexes, making a 'get' operation from Memcached. If the value
exists, it will be showed. If not, a exception will be thrown .


=cut


sub show {
    my ( $self, ) = @_;
    $self->load;
    if(!defined($self->size) || $self->size == 0){
        say "The queue '".$self->id_prefix."' is empty!";
    }
    else {
        my $first_index = $1 if $self->first =~ /(\d+)$/;
        my $last_index = $1 if $self->last =~ /(\d+)$/;
        foreach my $i($first_index .. $last_index){
            #mounting index for memcached
            my $mc_index = $self->id_prefix . $self->id . '_' . $i;
            my $value = $self->memcached->get($mc_index);
            if(!defined($value)){
                confess "An error occured trying make a 'get' operation. No value found for '$mc_index' index";
            }
            say "$i - $value" if defined($value);
        }
    }
}



=head2 cleanup()

Cleanup everything!


=cut


sub cleanup {
    my ( $self, ) = @_;
    $self->load;
    if(!defined($self->size) || $self->size == 0){
        say "The queue '".$self->id_prefix."' is empty!";
    }
    else {
        foreach my $i(1..$self->size){
            #mounting index for memcached
            my $mc_index = $self->id_prefix . $self->id . '_' . $i;
            my $value = $self->deq;
        }
    }
}



=head2 save($parameters)

WARNING! THIS IS A INTERNAL METHOD!  

Try to save queue pointers on Memcached. The parameters came on arrayref, when
each position of arrayref is a name of attribute that must be saved. This parameters 
are validated and then saved on memcached.

That makes the enqueuing process faster than save all parameters everytime, because
the input operations on Memcached are reduced.

Ex: $q->save(['name','first']);

The valid parameters are: 

=over

=item
name - Is the name of Queue;

=item
first - Is the first index of the key. Not the value, but the name of index;

=item
last - As the same way, this is the last index of the queue.

=back

If everything work well the method returns true. Otherwise returns false.

=cut

sub save {
    my ($self,$parameters) = @_;
    my $last = $self->last;
    my $ok = 0;
    if(ref($parameters) !~ /ARRAY/){
        confess "The parameters to save data MUST BE AN ARRAYREF";
    }
    foreach my $k(@{$parameters}){

        if($k !~ /^name|first|last|size|max_enq$/){
            confess "The parameter '$k' is invalid!";
        }
        else {
            my $index = '';
            my $prefix = $self->id_prefix;
            if($k !~ /$prefix/){
                $index = $prefix . $self->id . '_' . $k;
            }
            else {
                $index = $k;
            }
            if(!$self->memcached->set($index,$self->{$k})){
                cluck "Is not possible to save '$k' parameter! $@ $!";
            }
            else {
                $ok = 1;
            }
        }
    }
    return $ok;
}


=head1 AUTHOR

Andre Garcia Carneiro, C<< <bang at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-cache-memcached-queue at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Cache-memcached-Queue>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Cache::Memcached::Queue


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Cache-memcached-Queue>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Cache-memcached-Queue>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Cache-memcached-Queue>

=item * Search CPAN

L<http://search.cpan.org/dist/Cache-memcached-Queue/>

or send an e-mail to andregarciacarneiro@gmail.com


=back


=head1 TODO

 Test all stuff with threads.


=head1 LICENSE AND COPYRIGHT


This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

__PACKAGE__->meta->make_immutable;

1;    # End of Cache::Memcached::Queue
