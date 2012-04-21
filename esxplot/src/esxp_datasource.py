'''
Created on Apr 15, 2010

@author: l0r3zz
'''
import csv
import os
import wx
import logging
import collections
import time as Time

# use this string to format info on the loaded data set
fileinfostring_fmt="""
=================================
Loaded: {0}
Size: {1}
Start Time:{2}
End Time:{3}
Number of Metrics: {4}
Number of Samples: {5}
=================================
"""
#define a named tuple for esxtree data structure
T_node = collections.namedtuple("T_node","label vec")

class M_node :
    """ This Object will replace the T_node structure. It has a label and
    a vector, but each node can contain additional information
    like the stats for the column if it is a leaf node
    """
    def __init__(self, label="empty", vec=[],
                 mmin=0.0, mmax=0.0, mmean=0.0, m90th=0.0):
        self.label = label      #displayable name of the node
        self.vec = vec[:]       #if not None, vector of the children of the node
        self.colindex           #if vec is empty,  leaf node and  column index
        self.mmin = mmin        #statistics for the column...
        self.mmax = mmax
        self.mmean= mmean
        self.m90th = m90th

##### This is a good place to begin for 1.5 REFACTORING. Consider replacing 
##### this with a trie structure
class DataSource : ### candidate for refactoring for 1.1
    """ This class reads the data from the esxtop batch dump file
    which is in CSV format.  The file itself can be quite large
    (100s of Megabytes) and contain over 100K columns.  The constructor
    opens a dump file and builds a tree structure based on the column
    labels where categories  are delimited by a "\". The tree structure
    is built to facilitate UI navigation. Next the actual data is read
    in and placed in column arrays. For this version, we read the entire
    dataset into program memory.  Latter versions might try to do this lazily
    """

    def __init__(self, filearg) :

        self.log = logging.getLogger('esxplot.%s' % __name__)
        filedes = open(filearg)
        test = filedes.read(16)
        if test.find('"(PDH-CSV 4.0)') == -1: # is this a valid esxtop data set?
            filedes.close()
            error_txt = "Corrupt Header Information"
            self.log.error(error_txt)                    # nope
            raise ValueError(error_txt)


        row_num =sum(1 for row in filedes )        # count the number of rows
        filedes.seek(0)                            #reset the file 

        statinfo = os.stat(filearg)
        try:
            v = csv.reader(filedes)
        except:
            error_txt = "Not a csv file"
            self.log.error(error_txt)
            raise ValueError(error_txt)

        self.labels = v.next()                  # get the label descriptions
        # Initialize the t-node datastructure
        self.dRoot = HvTree('%%ESXTreeRoot%%')
        # No. of columns in the bundle (dataset has a "null" column at the end)
        self.colmag = len(self.labels)
        dlg =  wx.ProgressDialog ( 'Progress', 'Reading column labels.',
                                   maximum = (self.colmag*2),
                                   style=wx.PD_ELAPSED_TIME|wx.PD_AUTO_HIDE)
        for j in xrange(0, self.colmag):        # Loop through all of the labels
            #self.labels[j] += '\\ '+str(j)      # add the column index
            self.labels[j] = '%s\\ %s' % (self.labels[j],str(j)) # faster?
            if j%100 == 0 :
                dlg.Update( j )
        dlg.Update(self.colmag,"sorting...")
        sorted_labels = self.labels[1:]       # copy all except the time column
        dlg.Update(self.colmag+ self.colmag/2)
        sorted_labels.sort()               # sort the copy in alphabetical order
        # insert the time column back at the front
        sorted_labels.insert(0,self.labels[0])

        for j in xrange(1,self.colmag):
            # turn label into a list of path elements
            m = sorted_labels[j].split('\\')
            if len(m) < 4 :
                ##### silently ignoring the null column for the UI but
                # keeping it in the sorted_labels structure BEWARE!!!
                continue
            # add the path into the t-node tree, truncating the two
            # null elements at the front of the list
            self.dRoot.addMetric([ m[k] for k in xrange (2,len(m))])
            if j%100 == 0 :
                dlg.Update(self.colmag + j,"Building data structures" )

        # make it available to others (without the time column)
        self.l = sorted_labels[1:]

        # set up a list of lists
        self.columns = [[] for i in xrange( self.colmag)]
        # initialize the count of non-title (data) records read
        self.samplemag = 0

        # load the data into the columns array
        for row in v:
            # throw away a "malformed"  row and don't count it.
            if len(row) < self.colmag -1:
                self.log.warn("row %d  in %s was flagged as malformed" % (row, filearg))
                continue
            # changed to iterate over length of input data, because some
            # versions of esxtop write a null last row
            self.samplemag += 1          # count the number of records read
            for j in xrange(len(row)):
                self.columns[j].append(row[j])
            updt = int(self.colmag*2*self.samplemag/row_num)
            dlg.Update(updt,"Loading CSV Data" )

        if self.samplemag < 2:
            raise ValueError("Only one sample")

        timeformat = '%m/%d/%Y %H:%M:%S'


        # variables that are accessed by other classes and methods
        self.starttime = self.columns[0][0]
        self.endtime = self.columns[0][self.samplemag-1]
        st1 = Time.strptime(self.starttime,timeformat)
        st2 = Time.strptime(self.endtime,timeformat)
        t0 = Time.mktime(st1)
        t1 = Time.mktime(st2)
        self.timedelta = (t1 - t0)/self.samplemag
        self.time_axis = [0.0]
        for i in xrange(1,self.samplemag):
            self.time_axis.append(self.time_axis[i-1] +\
                Time.mktime(Time.strptime(self.columns[0][i], timeformat))\
                - Time.mktime(Time.strptime( self.columns[0][i-1], timeformat)))

        self.reQueries =[]  # list of regex queries entered
        self.v = v


        self.FileInfoString =\
            fileinfostring_fmt.format(
                                      filearg, str(statinfo.st_size),
                                      self.starttime, self.endtime,
                                      str(self.colmag), str(self.samplemag) )
        dlg.Update(self.colmag*2) # Take down the progress bar.
        dlg.Destroy()

        return

    def IsColZero(self,index):
        """
        Return true if all of the data is essentially zero
        """
        for value in self.columns[index]:
            if float(value)!= 0.0:
                return False
        return True

    def ColStats(self,index):
        """
        Return a tuple of basic statistics for the column, currently:
        Min, Max, Mean, 90th percentile
        """
        from scipy.stats import scoreatpercentile
        realvalues = [ float(x) for x in self.columns[index]]
        colmin = min( realvalues)
        colmax = max( realvalues)
        colmean = sum(realvalues)/ len(realvalues)
        col90th = scoreatpercentile(realvalues, 90)
        return colmin,colmax,colmean,col90th


    def AddQueryString(self,string):
        self.reQueries.append(string)
        return


class HvTree : ### candidate for refactoring for 1.1

    """ This Class is the actual class that creates a datastructure that
    the user navigates to find the actual column to graph We create a tree
    of T_nodes, a T_node is a tuple that looks like this...
        t_node = ( "label" , [ <list of T_nodes> | <integer> ] )
    the leaf t-node will always contain list with a single element of type
    integer which is an index into the esxtop column containing the data
    that is associated with the label path.

        Note: We may actually be able to build this data right into the
        treecntrl data structure
        and thus eliminate this class ( 2.0?)
    """

    def __init__(self,rootid) :
        self.root_node = T_node(rootid,[])

    def addMetric(self, path):
        """
        Add a metric into the representational database (Hvtree)
        there is a local function here _add, that is called recursively
        to walk the existing tree entries, this routine assumes that the tree
        has been built with a list of entries that have already bee sorted
        alphabetically
        """
        def _add(parent, path):
            parent = T_node(parent[0], parent[1])
            if len(path) == 1:
                parent.vec.append(path[0])
                return True
            if len(parent.vec) == 0 :    #nothing has been added yet
                parent.vec.append(T_node(path[0],[]) ) #add the child tuple
                _add(parent.vec[-1],path[1:])
                return True
            # crazy stuff to make loading faster, this only works with the
            # current layout of data
            if parent.vec[-1][0] == path[0]:
                _add(parent.vec[-1],path[1:])
                return True
            parent.vec.append(T_node(path[0],[])) # It's not here so add it
            _add(parent.vec[-1],path[1:])
            return True
        return _add(self.root_node,path)



    def isZero(self):
        if self.root_node[1] == []:
            return True
        else:
            return False