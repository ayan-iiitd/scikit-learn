# cython: cdivision=True
# cython: boundscheck=False
# cython: wraparound=False

# Authors: Gilles Louppe <g.louppe@gmail.com>
#          Peter Prettenhofer <peter.prettenhofer@gmail.com>
#          Brian Holt <bdholt1@gmail.com>
#          Noel Dawe <noel@dawe.me>
#          Satrajit Gosh <satrajit.ghosh@gmail.com>
#          Lars Buitinck
#          Arnaud Joly <arnaud.v.joly@gmail.com>
#          Joel Nothman <joel.nothman@gmail.com>
#          Fares Hedayati <fares.hedayati@gmail.com>
#          Jacob Schreiber <jmschreiber91@gmail.com>
#          Nelson Liu <nelson@nelsonliu.me>
#          Saif Ayan Khan <saifk@iiitd.ac.in>
#
# License: BSD 3 clause

from libc.stdio cimport printf
from libc.stdlib cimport calloc
from libc.stdlib cimport free
from libc.string cimport memcpy
from libc.string cimport memset
from libc.math cimport fabs

import numpy as np
cimport numpy as np
np.import_array()

from numpy.math cimport INFINITY
from scipy.special.cython_special cimport xlogy

from ._utils cimport log
from ._utils cimport safe_realloc
from ._utils cimport sizet_ptr_to_ndarray
from ._utils cimport WeightedMedianCalculator

# EPSILON is used in the Poisson criterion
cdef double EPSILON = 10 * np.finfo('double').eps

cdef class Criterion:
    #printf("HERE1\n")
    """Interface for impurity criteria.

    This object stores methods on how to calculate how good a split is using
    different metrics.
    """

    def __dealloc__(self):
        #printf("HERE2\n")
        """Destructor."""
        free(self.sum_total)
        free(self.sum_left)
        free(self.sum_right)
        
        #variables for sum of log for gamma

        #free(self.log_sum_total)
        free(self.log_sum_left)
        free(self.log_sum_right)
    
    def __getstate__(self):
        #printf("HERE3\n")
        return {}

    def __setstate__(self, d):
        #printf("HERE4\n")
        pass

    cdef int init(self, const DOUBLE_t[:, ::1] y, DOUBLE_t* sample_weight,
                  double weighted_n_samples, SIZE_t* samples, SIZE_t start,
                  SIZE_t end) nogil except -1:
        #printf("HERE5\n")
        """Placeholder for a method which will initialize the criterion.

        Returns -1 in case of failure to allocate memory (and raise MemoryError)
        or 0 otherwise.

        Parameters
        ----------
        y : array-like, dtype=DOUBLE_t
            y is a buffer that can store values for n_outputs target variables
        sample_weight : array-like, dtype=DOUBLE_t
            The weight of each sample
        weighted_n_samples : double
            The total weight of the samples being considered
        samples : array-like, dtype=SIZE_t
            Indices of the samples in X and y, where samples[start:end]
            correspond to the samples in this node
        start : SIZE_t
            The first sample to be used on this node
        end : SIZE_t
            The last sample used on this node

        """
        pass

    cdef int reset(self) nogil except -1:
        #printf("HERE6\n")
        """Reset the criterion at pos=start.

        This method must be implemented by the subclass.
        """
        pass

    cdef int reverse_reset(self) nogil except -1:
        #printf("HERE7\n")
        """Reset the criterion at pos=end.

        This method must be implemented by the subclass.
        """
        pass

    cdef int update(self, SIZE_t new_pos) nogil except -1:
        #printf("HERE8\n")
        """Updated statistics by moving samples[pos:new_pos] to the left child.

        This updates the collected statistics by moving samples[pos:new_pos]
        from the right child to the left child. It must be implemented by
        the subclass.

        Parameters
        ----------
        new_pos : SIZE_t
            New starting index position of the samples in the right child
        """
        pass

    cdef double node_impurity(self) nogil:
        #printf("HERE9\n")
        """Placeholder for calculating the impurity of the node.

        Placeholder for a method which will evaluate the impurity of
        the current node, i.e. the impurity of samples[start:end]. This is the
        primary function of the criterion class. The smaller the impurity the
        better.
        """
        pass

    #cdef void children_impurity(self, double* impurity_left,
    #                            double* impurity_right) nogil:

    cdef void children_impurity(self, double* impurity_left,
                                double* impurity_right,
                                double* log_impurity_left,
                                double* log_impurity_right) nogil:
        #printf("HERE10\n")
        """Placeholder for calculating the impurity of children.

        Placeholder for a method which evaluates the impurity in
        children nodes, i.e. the impurity of samples[start:pos] + the impurity
        of samples[pos:end].

        Parameters
        ----------
        impurity_left : double pointer
            The memory address where the impurity of the left child should be
            stored.
        impurity_right : double pointer
            The memory address where the impurity of the right child should be
            stored
        """
        pass

    #cdef void node_value(self, double* dest, double* log_dest) nogil:
    cdef void node_value(self, double* dest) nogil:
        #printf("HERE11\n")
        """Placeholder for storing the node value.

        Placeholder for a method which will compute the node value
        of samples[start:end] and save the value into dest.

        Parameters
        ----------
        dest : double pointer
            The memory address where the node value should be stored.

        """
        pass

    cdef double proxy_impurity_improvement(self) nogil:
        #printf("HERE12\n")
        """Compute a proxy of the impurity reduction.

        This method is used to speed up the search for the best split.
        It is a proxy quantity such that the split that maximizes this value
        also maximizes the impurity improvement. It neglects all constant terms
        of the impurity decrease for a given split.

        The absolute impurity improvement is only computed by the
        impurity_improvement method once the best split has been found.
        """
        cdef double impurity_left
        cdef double impurity_right
        cdef double log_impurity_left
        cdef double log_impurity_right
        self.children_impurity(&impurity_left, &impurity_right, &log_impurity_left, &log_impurity_right)

        return (- self.weighted_n_right * impurity_right
                - self.weighted_n_left * impurity_left)

    cdef double impurity_improvement(self, double impurity_parent,
                                     double impurity_left,
                                     double impurity_right) nogil:
        #printf("HERE13\n")
        """Compute the improvement in impurity.

        This method computes the improvement in impurity when a split occurs.
        The weighted impurity improvement equation is the following:

            N_t / N * (impurity - N_t_R / N_t * right_impurity
                                - N_t_L / N_t * left_impurity)

        where N is the total number of samples, N_t is the number of samples
        at the current node, N_t_L is the number of samples in the left child,
        and N_t_R is the number of samples in the right child,

        Parameters
        ----------
        impurity_parent : double
            The initial impurity of the parent node before the split

        impurity_left : double
            The impurity of the left child

        impurity_right : double
            The impurity of the right child

        Return
        ------
        double : improvement in impurity after the split occurs
        """
        return ((self.weighted_n_node_samples / self.weighted_n_samples) *
                (impurity_parent - (self.weighted_n_right /
                                    self.weighted_n_node_samples * impurity_right)
                                 - (self.weighted_n_left /
                                    self.weighted_n_node_samples * impurity_left)))


    

    
    



        


        

cdef class RegressionCriterion(Criterion):
    #printf("HERE14\n")
    r"""Abstract regression criterion.

    This handles cases where the target is a continuous value, and is
    evaluated by computing the variance of the target values left and right
    of the split point. The computation takes linear time with `n_samples`
    by using ::

        var = \sum_i^n (y_i - y_bar) ** 2
            = (\sum_i^n y_i ** 2) - n_samples * y_bar ** 2
    """

    def __cinit__(self, SIZE_t n_outputs, SIZE_t n_samples):
        #printf("HERE15\n")
        """Initialize parameters for this criterion.

        Parameters
        ----------
        n_outputs : SIZE_t
            The number of targets to be predicted

        n_samples : SIZE_t
            The total number of samples to fit on
        """
        # Default values
        self.sample_weight = NULL

        self.samples = NULL
        self.start = 0
        self.pos = 0
        self.end = 0

        self.n_outputs = n_outputs
        self.n_samples = n_samples
        self.n_node_samples = 0
        self.weighted_n_node_samples = 0.0
        self.weighted_n_left = 0.0
        self.weighted_n_right = 0.0

        self.sq_sum_total = 0.0

        ### variables for sum of log for gamma
        #self.log_sum_total = 0.0

        # Allocate accumulators. Make sure they are NULL, not uninitialized,
        # before an exception can be raised (which triggers __dealloc__).
        self.sum_total = NULL
        self.sum_left = NULL
        self.sum_right = NULL

        ### variables for sum of log for gamma
        #self.log_sum_total = NULL
        self.log_sum_left = NULL
        self.log_sum_right = NULL

        # Allocate memory for the accumulators
        self.sum_total = <double*> calloc(n_outputs, sizeof(double))
        self.sum_left = <double*> calloc(n_outputs, sizeof(double))
        self.sum_right = <double*> calloc(n_outputs, sizeof(double))

        ### variables for sum of log for gamma
        #self.log_sum_total = <double*> calloc(n_outputs, sizeof(double))
        self.log_sum_left = <double*> calloc(n_outputs, sizeof(double))
        self.log_sum_right = <double*> calloc(n_outputs, sizeof(double))

        #if (self.sum_total == NULL or
        #        self.sum_left == NULL or
        #        self.sum_right == NULL):
        if (self.sum_total == NULL or
                self.sum_left == NULL or
                self.sum_right == NULL or
                self.log_sum_left == NULL or
                self.log_sum_right == NULL):
            raise MemoryError()

    def __reduce__(self):
        printf("HERE16\n")
        return (type(self), (self.n_outputs, self.n_samples), self.__getstate__())

    cdef int init(self, const DOUBLE_t[:, ::1] y, DOUBLE_t* sample_weight,
                  double weighted_n_samples, SIZE_t* samples, SIZE_t start,
                  SIZE_t end) nogil except -1:
        #printf("HERE17\n")
        """Initialize the criterion.

        This initializes the criterion at node samples[start:end] and children
        samples[start:start] and samples[start:end].
        """
        # Initialize fields
        self.y = y
        self.sample_weight = sample_weight
        self.samples = samples
        self.start = start
        self.end = end
        self.n_node_samples = end - start
        self.weighted_n_samples = weighted_n_samples
        self.weighted_n_node_samples = 0.0

        cdef SIZE_t i
        cdef SIZE_t p
        cdef SIZE_t k
        cdef DOUBLE_t y_ik
        cdef DOUBLE_t w_y_ik
        cdef DOUBLE_t w = 1.0

        self.sq_sum_total = 0.0
        #self.log_sum_total = 0.0
        memset(self.sum_total, 0, self.n_outputs * sizeof(double))
        #memset(self.log_sum_total, 0, self.n_outputs * sizeof(double))

        for p in range(start, end):
            i = samples[p]

            if sample_weight != NULL:
                w = sample_weight[i]

            for k in range(self.n_outputs):
                y_ik = self.y[i, k]
                w_y_ik = w * y_ik
                self.sum_total[k] += w_y_ik

                ### log sum in array
                #self.log_sum_total[k] += log(w_y_ik)
                
                #self.log_sum_total += log(w_y_ik)

                self.sq_sum_total += w_y_ik * y_ik

            self.weighted_n_node_samples += w

        # Reset to pos=start
        self.reset()
        return 0

    cdef int reset(self) nogil except -1:
        #printf("HERE18\n")
        """Reset the criterion at pos=start."""
        cdef SIZE_t n_bytes = self.n_outputs * sizeof(double)
        memset(self.sum_left, 0, n_bytes)
        memcpy(self.sum_right, self.sum_total, n_bytes)

        self.weighted_n_left = 0.0
        self.weighted_n_right = self.weighted_n_node_samples
        self.pos = self.start
        return 0

    cdef int reverse_reset(self) nogil except -1:
        #printf("HERE19\n")
        """Reset the criterion at pos=end."""
        cdef SIZE_t n_bytes = self.n_outputs * sizeof(double)
        memset(self.sum_right, 0, n_bytes)
        memcpy(self.sum_left, self.sum_total, n_bytes)

        ### for log sums
        memset(self.log_sum_right, 0, n_bytes)
        memcpy(self.log_sum_left, self.sum_total, n_bytes)

        self.weighted_n_right = 0.0
        self.weighted_n_left = self.weighted_n_node_samples
        self.pos = self.end
        return 0

    cdef int update(self, SIZE_t new_pos) nogil except -1:
        #printf("HERE20\n")
        """Updated statistics by moving samples[pos:new_pos] to the left."""
        cdef double* sum_left = self.sum_left
        cdef double* sum_right = self.sum_right
        cdef double* sum_total = self.sum_total

        ### for log
        cdef double* log_sum_left = self.log_sum_left
        cdef double* log_sum_right = self.log_sum_right
        #cdef double* log_sum_total = self.log_sum_total

        cdef double* sample_weight = self.sample_weight
        cdef SIZE_t* samples = self.samples

        cdef SIZE_t pos = self.pos
        cdef SIZE_t end = self.end
        cdef SIZE_t i
        cdef SIZE_t p
        cdef SIZE_t k
        cdef DOUBLE_t w = 1.0

        # Update statistics up to new_pos
        #
        # Given that
        #           sum_left[x] +  sum_right[x] = sum_total[x]
        # and that sum_total is known, we are going to update
        # sum_left from the direction that require the least amount
        # of computations, i.e. from pos to new_pos or from end to new_pos.
        if (new_pos - pos) <= (end - new_pos):
            for p in range(pos, new_pos):
                i = samples[p]

                if sample_weight != NULL:
                    w = sample_weight[i]

                for k in range(self.n_outputs):
                    sum_left[k] += w * self.y[i, k]

                    ### log sum
                    log_sum_left[k] += log(w * self.y[i, k])

                self.weighted_n_left += w
        else:
            self.reverse_reset()

            for p in range(end - 1, new_pos - 1, -1):
                i = samples[p]

                if sample_weight != NULL:
                    w = sample_weight[i]

                for k in range(self.n_outputs):
                    sum_left[k] -= w * self.y[i, k]

                    #log sum
                    log_sum_left[k] -= log(w * self.y[i, k])

                self.weighted_n_left -= w

        self.weighted_n_right = (self.weighted_n_node_samples -
                                 self.weighted_n_left)
        for k in range(self.n_outputs):
            sum_right[k] = sum_total[k] - sum_left[k]

            ### log sum
            log_sum_right[k] = log(sum_total[k]) - log_sum_left[k]

        self.pos = new_pos
        return 0

    cdef double node_impurity(self) nogil:
        #printf("HERE21\n")
        pass

    #cdef void children_impurity(self, double* impurity_left,
    #                            double* impurity_right) nogil:
    cdef void children_impurity(self, double* impurity_left, double* impurity_right, double* log_impurity_left, double* log_impurity_right) nogil:
        #printf("HERE22\n")
        pass

    #cdef void node_value(self, double* dest, double* log_dest) nogil:
    cdef void node_value(self, double* dest) nogil:
        #printf("HERE23\n")
        """Compute the node value of samples[start:end] into dest."""
        cdef SIZE_t k

        for k in range(self.n_outputs):
            printf("AT DEST\n")
            printf("One - %f\n", self.sum_total[k] / self.weighted_n_node_samples)
            printf("Two - %f\n", log(self.sum_total[k]) / self.weighted_n_node_samples)
            #dest[k] = self.sum_total[k] / self.weighted_n_node_samples

            dest[k] = log(self.sum_total[k]) / self.weighted_n_node_samples

            
cdef class Self(RegressionCriterion):
    #printf("HERE24\n")
    """Mean squared error impurity criterion.

        MSE = var_left + var_right

        *** Changed to Gamma
    """
    
    cdef double node_impurity(self) nogil:
        #printf("HERE25\n")
        """Evaluate the impurity of the current node.

        Evaluate the MSE criterion as impurity of the current node,
        i.e. the impurity of samples[start:end]. The smaller the impurity the
        better.
        """
        cdef double* sum_total = self.sum_total

        #cdef double* log_sum_total = self.log_sum_total

        cdef double impurity

        cdef double log_impurity

        cdef SIZE_t k


        ### averagin square sum
        impurity = self.sq_sum_total / self.weighted_n_node_samples
        
        log_impurity = - 2 * self.log_sum_total / self.weighted_n_node_samples
        
        for k in range(self.n_outputs):

            ##subtracting squared of total
            impurity -= (sum_total[k] / self.weighted_n_node_samples)**2.0

            log_impurity -= 2 * log(sum_total[k] / self.weighted_n_node_samples)
        
        #printf('impurity - %f\n', impurity)
        #printf("***********************\n")

        ### Output checked, both coming fine

        #printf('log impurity - %f\n', log_impurity / self.n_outputs)
        #printf('impurity - %f\n', impurity / self.n_outputs)

        return impurity / self.n_outputs
        #return log_impurity / self.n_outputs

    cdef double proxy_impurity_improvement(self) nogil:
        #printf("HERE26\n")
        """Compute a proxy of the impurity reduction.

        This method is used to speed up the search for the best split.
        It is a proxy quantity such that the split that maximizes this value
        also maximizes the impurity improvement. It neglects all constant terms
        of the impurity decrease for a given split.

        The absolute impurity improvement is only computed by the
        impurity_improvement method once the best split has been found.
        """
        cdef double* sum_left = self.sum_left
        cdef double* sum_right = self.sum_right
        
        cdef double* log_sum_left = self.log_sum_left
        cdef double* log_sum_right = self.log_sum_right

        ## Tested, many times comes here

        #printf("Proxy Reqd")

        cdef SIZE_t k
        cdef double proxy_impurity_left = 0.0
        cdef double proxy_impurity_right = 0.0

        cdef double log_proxy_impurity_left = 0.0
        cdef double log_proxy_impurity_right = 0.0

        for k in range(self.n_outputs):

            ## squaring a side and adding it
            proxy_impurity_left += sum_left[k] * sum_left[k]
            proxy_impurity_right += sum_right[k] * sum_right[k]

            log_proxy_impurity_left += log(log_sum_left[k])
            log_proxy_impurity_right += log(log_sum_right[k])

        printf("Original - %f\n", proxy_impurity_left / self.weighted_n_left + proxy_impurity_right / self.weighted_n_right)

        printf("Log - %f\n", log_proxy_impurity_left / self.weighted_n_left + log_proxy_impurity_right / self.weighted_n_right)
        
        #return (proxy_impurity_left / self.weighted_n_left + proxy_impurity_right / self.weighted_n_right)
        return (log_proxy_impurity_left / self.weighted_n_left + log_proxy_impurity_right / self.weighted_n_right)

    #cdef void children_impurity(self, double* impurity_left,
    #                            double* impurity_right) nogil:
    cdef void children_impurity(self, double* impurity_left, double* impurity_right, double* log_impurity_left, double* log_impurity_right) nogil:
        #printf("HERE27\n")
        """Evaluate the impurity in children nodes.

        i.e. the impurity of the left child (samples[start:pos]) and the
        impurity the right child (samples[pos:end]).
        """
        cdef DOUBLE_t* sample_weight = self.sample_weight
        cdef SIZE_t* samples = self.samples
        cdef SIZE_t pos = self.pos
        cdef SIZE_t start = self.start

        cdef double* sum_left = self.sum_left
        cdef double* sum_right = self.sum_right

        cdef double* log_sum_left = self.log_sum_left
        cdef double* log_sum_right = self.log_sum_right
        cdef DOUBLE_t y_ik

        cdef double sq_sum_left = 0.0
        cdef double sq_sum_right

        """cdef double log_sum_left = 0.0
        cdef double log_sum_right"""

        cdef SIZE_t i
        cdef SIZE_t p
        cdef SIZE_t k
        cdef DOUBLE_t w = 1.0

        for p in range(start, pos):
            i = samples[p]

            if sample_weight != NULL:
                w = sample_weight[i]

            for k in range(self.n_outputs):
                
                y_ik = self.y[i, k]

                ## squaring actual y values again
                ## could be the first part, sum over y_i**2 upto n

                ## WRITING FOR GAMMA
                sq_sum_left += w * y_ik * y_ik

                #log_sum_left += log(w * y_ik)
 
        sq_sum_right = self.sq_sum_total - sq_sum_left
        
        #log_sum_right = self.log_sum_total - log_sum_left

        ## taking avg again
        impurity_left[0] = sq_sum_left / self.weighted_n_left
        impurity_right[0] = sq_sum_right / self.weighted_n_right

        """log_impurity_left[0] = -2 * log_sum_left / self.weighted_n_left
        log_impurity_right[0] = -2 * log_sum_right / self.weighted_n_right"""

        for k in range(self.n_outputs):
            
            ## squaring again
            ## probably the second part where it is n*(Y_bar)**2 and sum_let or right is the first part of equation
            impurity_left[0] -= (sum_left[k] / self.weighted_n_left) ** 2.0
            impurity_right[0] -= (sum_right[k] / self.weighted_n_right) ** 2.0

            log_impurity_left[0] = ((log_sum_left[k] / self.weighted_n_left) * 2.0) - (2 * log_sum_left[k] / self.weighted_n_left)
            log_impurity_right[0] = ((log_sum_right[k] / self.weighted_n_right) * 2.0) - (2 * log_sum_right[k] / self.weighted_n_right)

        ## taking avg again
        impurity_left[0] /= self.n_outputs
        impurity_right[0] /= self.n_outputs

        log_impurity_left[0] /= self.n_outputs
        log_impurity_right[0] /= self.n_outputs