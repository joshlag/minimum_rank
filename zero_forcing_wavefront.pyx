include 'sage/ext/stdsage.pxi'
include 'sage/ext/cdefs.pxi'
include 'sage/ext/interrupt.pxi'

"""
Fast computation of zero forcing sets
"""

#######################################################################
#
# Copyright (C) 2009 Tracy Hall, Jason Grout, and Josh Lagrange.
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses/.
#######################################################################


include "sage/misc/bitset_pxd.pxi"
include "sage/misc/bitset.pxi"
from sage.misc.bitset cimport FrozenBitset, Bitset

cdef update_wavefront(bitset_s *neighbors,bitset_s *unfilled):
    """
    Run zero forcing as much as possible
    """
    cdef bitset_t unfilled_neighbors
    cdef bitset_t filled_active
    cdef bitset_t filled_active_copy
    
    # Initialize filled_active to the complement of unfilled
    bitset_init(filled_active, unfilled.size)
    bitset_complement(filled_active, unfilled)

    bitset_init(filled_active_copy, unfilled.size)
    bitset_init(unfilled_neighbors, unfilled.size)

    cdef int new_filled, n
    
    cdef int done = 0
    
    while done != 1:
        done = 1
        bitset_copy(filled_active_copy, filled_active)
        n = bitset_first(filled_active_copy)
        while n>=0:
            bitset_intersection(unfilled_neighbors, &neighbors[n], unfilled)
            new_filled = bitset_first(unfilled_neighbors)
            if new_filled < 0:
                # no unfilled neighbors
                bitset_discard(filled_active, n)
            else:
                # look for second unfilled neighbor
                if bitset_next(unfilled_neighbors, new_filled+1) < 0:
                    # No more unfilled neighbors
                    bitset_add(filled_active, new_filled)
                    bitset_remove(unfilled, new_filled)
                    bitset_remove(filled_active, n)
                    done = 0
            n = bitset_next(filled_active_copy, n+1)
    
    # Free all memory used:
    bitset_free(filled_active)
    bitset_free(unfilled_neighbors)
    bitset_free(filled_active_copy)
            
from sage.graphs.all import Graph            

def zero_forcing_set_wavefront(matrix):
    """
    Calculate a zero forcing set.

    INPUT:

    a graph


    OUTPUT:

    A zero forcing set as a frozen set
    
    
    EXAMPLE::
        sage: zero_forcing_set(graphs.PetersenGraph().am())
        frozenset([8, 0, 4, 5, 6])
    """
    if isinstance(matrix, Graph):
        matrix = matrix.adjacency_matrix()
    cdef int n, i, j, v, budget, can_afford
    cdef bool found_optimal_set = false
    cdef int num_vertices = matrix.nrows()
    cdef list zero_forcing_vertices = []
    cdef list zero_forcing_sets = []
    cdef bitset_t unfilled_neighbors
    cdef bitset_s *initial_set, *unfilled_set, *closure_to_add_unfilled, *closure_to_add_initial
    cdef bitset_s *neighbors
    
    # closures is a dictionary mapping closures (unfilled sets) to the initial zfs sets
    closures = dict()
    
    cdef bitset_s *neighbors_set = <bitset_s *> sage_malloc(num_vertices*sizeof(bitset_s))

    cdef Bitset closure_to_add_initial_Bitset, initial_Bitset
    cdef FrozenBitset closure_to_add_unfilled_Bitset, unfilled_Bitset

    cdef int cost

    cdef int minimum_degree = min([len(matrix.nonzero_positions_in_row(i)) for i in range(num_vertices)])


    # Initialize the neighbors_set; neighbors[n] is a bitset of the neighbors
    #cdef list neighbors_set = [set(matrix.nonzero_positions_in_row(i)) for i in range(matrix.nrows())]
    for i in range(num_vertices):
        bitset_init(&neighbors_set[i], num_vertices)
        bitset_clear(&neighbors_set[i])
        for j in matrix.nonzero_positions_in_row(i):
            bitset_add(&neighbors_set[i], j)
    
    
    initial_Bitset = Bitset(None, capacity=num_vertices)
    unfilled_Bitset = FrozenBitset(None, capacity=num_vertices)
    unfilled_set = unfilled_Bitset._bitset    
    # Set unfilled_set to include all vertices
    bitset_complement(unfilled_set, unfilled_set)
    closures[unfilled_Bitset] = initial_Bitset    

    bitset_init(unfilled_neighbors, num_vertices)

    # We have to fill at least one vertex to start, so budget >= 1
    for budget in range(minimum_degree,num_vertices+1):
    
        #Check to see if we have found an optimal zero forcing set already.
        #If so, break out of for loop
        if found_optimal_set:
            break;
        
        #print "current budget: ", budget, " Current closures: ", len(closures)
        for unfilled_Bitset, initial_Bitset in closures.items():
            initial_set = initial_Bitset._bitset
            unfilled_set = unfilled_Bitset._bitset
            can_afford = budget - bitset_len(initial_set)
            #print "from here, can afford cost of: ", can_afford

            # OPTIMIZATION: pick one vertex from unfilled_set from each orbit of the point-wise 
            # stabilizer of the filled vertices? No need to go through every unfilled vertex---
            # just pick one from each orbit.  Or at very least, 
            # test to see if any permutations in that stabilizer push this vertex to a lower number 
            # (i.e., we've looked at essentially the same vertex before now).  
            # We may not have time to calculate the entire stabilizer, but 
            # we can calculate a bunch of permutations from it to do a minimal check.
            # Probably, we should calculate the orbits once per closure and 
            # store that with the closure and use that as "unfilled_set" above.
            
            # Consider all possible vertices
            for n in range(num_vertices):
                #while n>=0:
                #print "Examining vertex ",n
                neighbors = &neighbors_set[n]
                bitset_intersection(unfilled_neighbors, neighbors, unfilled_set)

                cost = max(1, bitset_len(unfilled_neighbors))
                if not bitset_in(unfilled_set, n):
                    cost -= 1
                    if cost==0:
                        #print "vertex %d is zero-cost; skipping"%n
                        continue
                if(cost<=can_afford):
                    #print "  We can afford to add vertex ", n
                    # point to two new (uninitialized) closure spots
                    #print "  adding closure ", num_current_closures + num_closures_to_add
                    closure_to_add_initial_Bitset = Bitset(None, capacity=num_vertices)
                    closure_to_add_unfilled_Bitset = FrozenBitset(None, capacity=num_vertices)
                    closure_to_add_initial = closure_to_add_initial_Bitset._bitset
                    closure_to_add_unfilled = closure_to_add_unfilled_Bitset._bitset

                    bitset_copy(closure_to_add_initial, initial_set)
                    
                    if bitset_in(unfilled_set, n):
                        bitset_add(closure_to_add_initial, n)
                        
                    # We add all neighbors now so that we save a step in the "update" step below
                    # We will discard one of the neighbors, if needed, below.
                    bitset_union(closure_to_add_initial, closure_to_add_initial, unfilled_neighbors)

                    bitset_copy(closure_to_add_unfilled, unfilled_set)
                    bitset_difference(closure_to_add_unfilled, closure_to_add_unfilled, closure_to_add_initial)
                    #print "  before calling zfs algorithm, unfilled is: ", bitset_string(closure_to_add_unfilled)
                    update_wavefront(neighbors_set, closure_to_add_unfilled)
                    #print "  after running zfs: ", bitset_string(closure_to_add_unfilled)

                    # subtract one unfilled neighbor from the initial zero forcing set, 
                    # since we got that one for free with zero forcing
                    if not bitset_isempty(unfilled_neighbors):
                        bitset_discard(closure_to_add_initial, bitset_first(unfilled_neighbors))
                        
                    #print "  new initial zfs set: ", bitset_string(closure_to_add_initial)

                    if (bitset_isempty(closure_to_add_unfilled)):
                    	found_optimal_set = true
                        # We found a zero forcing set that fills the graph
                        
			            #Place it into the set of optimal zero forcing sets if it is not already there
			            if frozenset(closure_to_add_initial_Bitset) not in zero_forcing_sets:
				            zero_forcing_sets.append(frozenset(closure_to_add_initial_Bitset))


                if closure_to_add_unfilled_Bitset not in closures:
                    closures[closure_to_add_unfilled_Bitset] = closure_to_add_initial_Bitset
                #else:
                    #print "Found matching closure", closure_to_add_unfilled_Bitset, " old zfs: ", closures[closure_to_add_unfilled_Bitset], " new zfs: " , closure_to_add_initial_Bitset
                # Change to include all vertices not in the initial set
                #n = bitset_next(unfilled_set, n+1)
    
    #We will always find an optimal zero forcing set since all the vertices colored black would be a zero forcing set.
	#return the set of all optimal zero forcing sets
    # Free all my memory
    for i in range(num_vertices):
        bitset_free(&neighbors_set[i])
    sage_free(neighbors_set)

    bitset_free(unfilled_neighbors)
    return zero_forcing_sets, len(closures)