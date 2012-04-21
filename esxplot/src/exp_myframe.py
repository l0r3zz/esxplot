'''
Created on Apr 20, 2012

@author: l0r3zz
'''
version = "esxplot v1.5-04202012"
copyright = """
(c)Copyright 2009 VMware Inc.
(c)Copyright 2012 Geoff White

This program is free software: you can redistribute it
and/or modify it under the terms of the GNU General
Public License as published by the Free Software
Foundation, either version 2 of the License, or any
later version.

This program is distributed in the hope that it will
be useful, but WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public
License along with this program.  If not, see
<<http://www.gnu.org/licenses/>>.

geoffw@durganetworks.com
---
"""

# use this string to print out stats on selected metrics

minmaxavg_fmt = """{0}
Min: {1},  Max: {2},  Mean: {3:8.5},  90th Percentile: {4:8.5}
---
"""


# Tuneables
MAXQUERYLENGTH = 4096  # Maximum size of a regex query
MAXDisplayQueryLength = 20


#import exp_mylog
import logging
import wx
import wx.html
import wx.lib.plot as wxPlot
import sys
import os
import re
import esxp_gui
#from optparse import OptionParser

from scipy.stats import scoreatpercentile
import exp_manpage
import csv
import esxp_datasource

class MyFrame(esxp_gui.EsxPlotFrame):
    '''This is the main "work horse" class. Most of the methods called
    here do the brunt of the displaying and receive all of the input.
    '''
    def __init__(self, parent, iid, title, csvl):
        '''Initialize our window, create all panel and widgets '''
        # discover what kind of OS we are running on
        self.isWindowsG = True if os.name == 'nt' else False
        self.log = logging.getLogger('esxplot.%s' % __name__)
        esxp_gui.EsxPlotFrame.__init__(self, parent, iid, title,
                          wx.DefaultPosition, wx.Size(900, 450))

        self.datavector = csvl  # current dataset object reference
                                # this might become an array in future
                                # versions that deal with multiple datasets
        self.dirname = ''       # initialize for sticky directories
        self.filename = ''      # holder for filename


        # Initial preferences and parameters
        self.lgndlen = -1
        self.line_width = 1
        self.abbrv_lgd = False
        self.isGraphPresent = False  # nothing plotted yet
        self.isDatasetLoaded = False
        self.HelpIsLive = None      # True if Help window is open
        self.exp_column_dir = ""    # Holds the last directory specified by
                                    # user on CSV export
        self.itemlist = []           # array to hold multiple selections

        self.default_color = ( 'midnightblue', 'red', 'thistle', 'brown',
                               'purple', 'goldenrod', 'orangered',
                               'springgreen',
                               'steelblue', 'peru', 'orange', 'deeppink',
                               'chartreuse', 'cyan', 'fuchsia', 'maroon')
        self.color = list(self.default_color[:])

        # Bring up the GUI
        # the elements referenced here are defined in
        # esxp_gui_custom.py where the parent class is defined
        self.banner.SetLabel(label=version)
        self.menu.Append(esxp_gui.ID_ABOUT, "&About",version)
        # enable the zoom feature (drag a box around area of interest)
        self.plotter.SetEnableZoom(True)
        # Set the font size of the Title
        self.plotter.SetFontSizeTitle(12)
        # Enable Legends
        self.plotter.SetEnableLegend(True)
        # set up the Grid and tell MyPlotCanvas whether we're
        # running Windows or not
        self.plotter.SetEnableGrid(True)
        self.plotter.SetGridColour('LIGHT GREY')
        self.plotter.SetOS(self.isWindowsG)
        # Register call back routines for various UI elements here
        wx.EVT_MENU(self, esxp_gui.ID_EXIT,  self.TimeToQuit)
        wx.EVT_MENU(self, esxp_gui.ID_ABOUT,  self.OnAbout)
        wx.EVT_MENU(self, esxp_gui.ID_IMPORT_DATA_BATCH,  self.OnImportData)
        wx.EVT_MENU(self, esxp_gui.ID_IMPORT_QUERIES, self.OnImportQueries)
        wx.EVT_MENU(self, esxp_gui.ID_PREF,  self.OnPrefs)
        wx.EVT_MENU(self, esxp_gui.ID_EXPORT_GRAPHS,  self.OnExportGraphs)
        wx.EVT_MENU(self, esxp_gui.ID_EXPORT_COLS, self.OnExportColumns)
        wx.EVT_MENU(self, esxp_gui.ID_EXPORT_QUERIES, self.OnExportQueries)
        wx.EVT_MENU(self, esxp_gui.ID_CLOSE_DATASET, self.OnCloseDataset)
        wx.EVT_MENU(self, esxp_gui.ID_HELP,self.OnHelp)

        # Bind the OnSelChanged method to the tree
        self.tree.Bind(wx.EVT_TREE_SEL_CHANGED, self.OnSelection, id=1)
        # Bind the right click event (for query result set deletion)
        self.tree.Bind(wx.EVT_TREE_ITEM_RIGHT_CLICK, self.OnRightClick,
                       id=wx.ID_ANY)
        # Bind the OnSearchQuery method to the textctrl widget,
        # bind it to the EVT_BUTTON event
        self.queryButton.Bind(wx.EVT_BUTTON, self.OnSearchQuery, id=wx.ID_ANY)
        # Make sure we clean up any stray windows on the way out
        self.Bind(wx.EVT_CLOSE, self.OnCloseHelp)
        self.SetStatusText(version)
        self.MyTextUpdate([version, copyright])
        self.MyTextUpdate("wxPython version = " + wx.VERSION_STRING)

        ###### HACK ALERT ################
        # Datasource is called at the top level to read in the csv files and build the
        # Initial in memory datastructure containing the actual data, tree.MyTreeLoad(csv)
        # Is called to actually load the selection pane, these two need to be re-written

        if csvl != None: #if there is data loaded load the treectrl
            self.tree.MyTreeLoad(csvl)
            self.MyTextUpdate(csvl.FileInfoString)

        # Create the window in the center of the screen
        #self.Centre()

        return



    def MyAlert(self, message):
        """
        Print an alert on the screen, dismiss by clicking OK
        """
        dlg = wx.MessageDialog(self, message,"Warning!",
                               wx.OK | wx.ICON_INFORMATION)
        #log("Warning!: "+message)
        dlg.ShowModal()
        dlg.Destroy()
        return

    def MyDialog(self, message):
        """
        Brink up a dialog, require yes/no answer
        """
        dlg = wx.MessageDialog(self, message, "Response Required!", wx.YES_NO)
        val = dlg.ShowModal()
        dlg.Destroy()
        if val == wx.ID_NO:
            return False
        return True

    def MyTextUpdate(self,message):
        """
        Update the esxplot status window
        """
        if isinstance(message, str):
            self.textbox.AppendText(message)
            self.log.warn("Console Status: %s" % message)
        elif isinstance (message, list):
            for m in message:
                self.MyTextUpdate(m)
        return



# Call back routines
####################


    #Menu callbacks
    def TimeToQuit(self, event):
        """
        Exit the applixation
        """
        if self.HelpIsLive:
            self.HelpIsLive.Destroy()    #Destroy any Help windows lying around
        self.Close(True)                 # esxplot has left the building

    def OnCloseHelp(self, event):
        if self.HelpIsLive:
            self.HelpIsLive.Destroy()    #Destroy any Help windows lying around
        self.Destroy()


    def OnAbout(self, event):
        """
        Display an about message through a Message Dialog
        """
        about_text = version + "\n" + copyright
        dlg = wx.MessageDialog(self, about_text, "About Me",
                               wx.OK | wx.ICON_INFORMATION)
        dlg.ShowModal()
        dlg.Destroy()

    def OnPrefs(self,event):
        '''
        Called when the User selects the Preference menu item.
        Put all preferences, switches, dials and knobs, here.
        Uses the Dialog designed with wxGlade imported from esxp_gui.py
        '''
        def _load_colors():
            '''
            load the colors into the preferences panel from the frame object
            '''

            #self.color = list(self.default_color)
            dlg.tcl_rgb1.SetValue(self.color[0])
            dlg.tcl_rgb2.SetValue(self.color[1])
            dlg.tcl_rgb3.SetValue(self.color[2])
            dlg.tcl_rgb4.SetValue(self.color[3])
            dlg.tcl_rgb5.SetValue(self.color[4])
            dlg.tcl_rgb6.SetValue(self.color[5])
            dlg.tcl_rgb7.SetValue(self.color[6])
            dlg.tcl_rgb8.SetValue(self.color[7])

            dlg.tcl_rgb9.SetValue(self.color[8])
            dlg.tcl_rgb10.SetValue(self.color[9])
            dlg.tcl_rgb11.SetValue(self.color[10])
            dlg.tcl_rgb12.SetValue(self.color[11])
            dlg.tcl_rgb13.SetValue(self.color[12])
            dlg.tcl_rgb14.SetValue(self.color[13])
            dlg.tcl_rgb15.SetValue(self.color[14])
            dlg.tcl_rgb16.SetValue(self.color[15])
            return

        def _color_reset(event):
            '''
            Reset the colors to the initial defaults when the button is pushed
            '''
            self.color = list(self.default_color)
            _load_colors()
            return

        # call the Dialog constructor created by wxGlade
        dlg = esxp_gui.EsxPlotPreferencesDialog(None, -1)
        dlg.button_color_reset.Bind(wx.EVT_BUTTON, _color_reset, id=wx.ID_ANY)

        if self.line_width == 1:
            dlg.radio_linew1.SetValue(True)
        else:
            dlg.radio_linew2.SetValue(True)

        if self.abbrv_lgd:
            dlg.chkb_lgd.SetValue(True)
            dlg.tcl_lgd.SetValue(str(self.lgndlen) )
        else:
            dlg.chkb_lgd.SetValue(False)
            dlg.tcl_lgd.SetValue(str(" "))

        # Load colors that have been saved
        _load_colors()

        # If the user pressed OK, there may be preference changes to process
        if dlg.ShowModal()== wx.ID_OK:
            if dlg.radio_linew1.GetValue():
                self.line_width = 1
            else:
                self.line_width = 2
            if dlg.chkb_lgd.GetValue():
                self.abbrv_lgd = True
                try:
                    rval = int(dlg.tcl_lgd.GetValue())
                except ValueError:
                    self.MyAlert("illegal legend length, not changed")
                    rval = self.lgndlen
                self.lgndlen = rval

            else:
                self.abbrv_lgd = False
                self.lgndlen = -1

            if self.lgndlen > 100:
                self.lgndlen = 100
            elif self.lgndlen < -1:
                self.lgndlen = -1
                self.abbrv_lgd = False

            # save the colors in case they were changed.
            self.color[0] = dlg.tcl_rgb1.GetValue()
            self.color[1] = dlg.tcl_rgb2.GetValue()
            self.color[2] = dlg.tcl_rgb3.GetValue()
            self.color[3] = dlg.tcl_rgb4.GetValue()
            self.color[4] = dlg.tcl_rgb5.GetValue()
            self.color[5] = dlg.tcl_rgb6.GetValue()
            self.color[6] = dlg.tcl_rgb7.GetValue()
            self.color[7] = dlg.tcl_rgb8.GetValue()
            self.color[8] = dlg.tcl_rgb9.GetValue()
            self.color[9] = dlg.tcl_rgb10.GetValue()
            self.color[10] = dlg.tcl_rgb11.GetValue()
            self.color[11] = dlg.tcl_rgb12.GetValue()
            self.color[12] = dlg.tcl_rgb13.GetValue()
            self.color[13] = dlg.tcl_rgb14.GetValue()
            self.color[14] = dlg.tcl_rgb15.GetValue()
            self.color[15] = dlg.tcl_rgb16.GetValue()

            self.MyTextUpdate("%Preferences have changed\n")
        else:
            pass

        dlg.Destroy()

        self.OnSelection(event)  #redraw the plot with new preferences
        return

    def OnHelp(self,event):
        if self.HelpIsLive:
            dlg = self.HelpIsLive
        else:
            dlg = MyHelpDialog()

        html = wx.html.HtmlWindow(dlg, pos=(10, 10), size=(780, 430),
                                  style=wx.html.HW_SCROLLBAR_AUTO )
        html.SetStandardFonts()
        html.SetPage(exp_manpage.man_page )
        dlg.Show()
        self.HelpIsLive = dlg
        return

    def OnImportData(self, event): ### candidate for refactoring for 1.1
        """
        Get a file containing data from the user
        """

        if self.isDatasetLoaded:
            self.MyAlert("A data set has already been loaded")
            return


        dlg = wx.FileDialog(self, "esxtop batch output file",
                            self.dirname, "", "*.*", wx.OPEN)

        if dlg.ShowModal()==wx.ID_OK:
            self.filename=dlg.GetFilename()
            self.dirname=dlg.GetDirectory()
            dlg.Destroy()

        if self.filename != '':
            fpath = self.dirname+'/'+self.filename

            if os.path.exists(fpath) == False:
                print("?File not found - "+sys.argv[1])
                exit()


            try:
                # we have a valid filename, let's get this Party started
        ###### HACK ALERT ################
        # Datasource is called at the top level to read in the csv files and build the
        # Initial in emory datastructure containing the actual data, tree.MyTreeLoad(csv)
        # Is called to actually load the selection pane, these two need to be re-written
                v = esxp_datasource.DataSource( fpath)
            except (ValueError,csv.Error)as err:
                self.MyAlert(fpath + " doesn't seem to be an estop data set,"\
                   + str(err))
                return

            self.datavector = v # set datavector so other
                                # methods can find the info
            self.tree.MyTreeLoad(v)        # bring up the GUI
            self.MyTextUpdate(self.datavector.FileInfoString)
            self.isDatasetLoaded = True
            return


    def OnImportQueries(self, event):
        """
        Load saved queries from a file
        """

        if self.datavector == None:
            self.MyAlert("You need to load a dataset first!")
            return

        dirname = ''
        filename = ''
        dlg = wx.FileDialog(self, "Saved Queries file", dirname,
                            "", "*.*", wx.OPEN)

        if dlg.ShowModal()==wx.ID_OK:
            filename=dlg.GetFilename()
            dirname=dlg.GetDirectory()
            dlg.Destroy()

        if filename != '':
            fpath = dirname + '/' + filename

            if os.path.exists(fpath) == False:
                self.MyAlert("?File not found - " + sys.argv[1])
                return
            f = open(fpath,"rb")
            rawqueries = f.readlines()        # read the entire query file
            if not re.match("#%%esxplot:queries%%", rawqueries[0]):
                self.MyAlert(fpath +\
                   " doesn't seem to be an saved queries file")
                return
        v = [ q.strip('"\n') for q in rawqueries[1:]]
        for QueryString in v:
            self._applyQuery(QueryString, "GREEN")
        return




    def OnExportGraphs(self, event):
        """
        Export the plot to a graphis image file
        """
        if self.isGraphPresent:
            self.plotter.SaveFile()
        else:
            self.MyAlert("You need to plot something first")
        return

    def OnExportColumns(self, event):
        """
        Export selected columns to a CSV file
        """

        itemlist = self.tree.GetSelections()
        if len(itemlist) == 0:                  #no selections were made
            self.MyAlert("You need to select something first")
            return

        dlg = wx.FileDialog ( None, defaultDir=self.exp_column_dir,
                             style = wx.FD_SAVE|wx.FD_OVERWRITE_PROMPT )
        if dlg.ShowModal() == wx.ID_OK:
            filename=dlg.GetFilename()
            dirname=dlg.GetDirectory()
            self.exp_column_dir = dirname
            dlg.Destroy()
            if filename != '':
                fpath = dirname+'/'+filename
            else:
                self.MyAlert("No file specified")
                return
            if os.path.exists(fpath):
                if not self.MyDialog("File exist, Overwrite?"):
                    return

            try:
                fildes = open(fpath, 'wb')
            except:
                self.MyAlert("File " + fpath +\
                    " could not be opened for writing, check permissions")
                return
            # open the csv file to write the selections to
            # make the output reloadable to esxplot
            v = csv.writer(fildes, quoting=csv.QUOTE_ALL, dialect="excel",
                           lineterminator=',\r\n')


            columnlist = ['0'] # we always dump the time column
            traversal_result = []
            for item in itemlist:
                traversal_result.extend(self.tree.MyTreeLeafList(item))
            for item in traversal_result:
                columnindex = self.tree.GetPyData(item)
                if columnindex == None:
                    continue
                columnlist.append(columnindex)

            l = [ self.datavector.labels[int(x)] for x in columnlist]
            labelinfo = [ x.rsplit('\\',1)[0] for x in l]
            v.writerow(labelinfo)        #write out the label information

            for i in xrange(self.datavector.samplemag):
                rowvalues =\
                   [str(self.datavector.columns[int(x)][i]) for x in columnlist]
                v.writerow(rowvalues)

            fildes.close()

        return

    def OnExportQueries(self,event):
        """
        Export the current query set to a query file that can be loaded later
        """
        if not self.datavector:
            self.MyAlert("No queries are loaded")
            return

        if not self.datavector.reQueries:
            self.MyAlert("You need some Queries to Export!")
            return

        dlg = wx.FileDialog ( None, style = wx.OPEN )
        if dlg.ShowModal() == wx.ID_OK:
            filename=dlg.GetFilename()
            dirname=dlg.GetDirectory()
            dlg.Destroy()
            if filename != '':
                fpath = dirname+'/'+filename
            else:
                self.MyAlert("No file specified")
                return
            if os.path.exists(fpath):
                if not self.MyDialog("File exist, Overwrite?"):
                    return
            try:
                fildes = open(fpath,'wb')
            except:
                self.MyAlert("File " + fpath +\
                    " could not be opened for writing, check permissions")
                return
            fildes.write("#%%esxplot:queries%% " + version + " Saved Queries\n")
            for q in self.datavector.reQueries:
                fildes.write('"' + q + '"\n')
            fildes.close()
        return

    # Widget Call backs
    def OnSelection(self, event):
        '''
        Method called when selected item is changed ( click on a metric and
        it will be plotted.  This is the main routine that does the plotting
        '''


        selectionlist =\
            [ self.tree.GetPyData(x)  for x in self.tree.GetSelections()\
                if self.tree.GetPyData(x) != None ] #filter out trunk selections
        #log("SelectionList = "+str(selectionlist))
        if len(selectionlist) == 0:                  #no selections were made
            self.itemlist = []
            return

        if len(selectionlist) > len(self.color): #too many selections were made
            self.MyAlert("You can only plot a maximum of " +\
                str(len(self.color))+" metrics in a single graph")
            return

        if len(selectionlist) == 1:
            # stupid windows implementation sends bogus
            # event on multiple selection
            if (len(self.itemlist) == 1) and (self.isWindowsG):
                return
            self.itemlist= selectionlist[:]
        else:
            self.itemlist.extend(list(set(selectionlist) - set(self.itemlist)))

        colorindex = 0
        line = []
        for item in self.itemlist:
            columnindex = item

            # User selected a non-leaf node, (no data present)
            if columnindex == None:
                continue

            # Make sure, it's an integer and not a string object
            columnindex = int(columnindex)

            # reference the column data list, the number of samples
            # and the time quanta from the DataSource object
            columndata = self.datavector.columns[columnindex]
            numberofsamples = self.datavector.samplemag
            timequanta = round(self.datavector.timedelta)
            labelinfo = self.datavector.labels[columnindex].split('\\')
            title = labelinfo[2]
            legend = labelinfo[3] + ': ' + labelinfo[4]

            if (self.lgndlen>0) & (len(legend) > self.lgndlen):
                    legend = "..."+legend[len(legend)-self.lgndlen:]
            elif (self.lgndlen == 0):
                legend = ""

            # use a list comprehension with xrange to create the
            # co-ordinate tuples
            data = [(self.datavector.time_axis[x-1],\
                float(columndata[x])) for x in xrange (1, numberofsamples)]

            float_data = [float(columndata[x])\
                for x in xrange(1, numberofsamples)]

            # draw points as a line
            line.append(wxPlot.PolyLine(data,
                        legend=legend,
                        colour=self.color[colorindex%len(self.color)],
                        width=self.line_width))
            colorindex += 1

            mmm= minmaxavg_fmt.format(labelinfo[3] + "/" + labelinfo[4],
                                      min(float_data), max(float_data),
                                      sum(float_data)/len(float_data),
                                      scoreatpercentile(float_data, 90) )

            self.MyTextUpdate(mmm)
        #Label for the X axis
        xaxislabel = 'Time(sec) : Start Time: ' + self.datavector.starttime +\
            '  :  End Time: ' +\
            self.datavector.endtime + ' : Sample period = ' +\
            str(timequanta) + ' seconds'

        #Instantiate the Graphics Context
        gc = wxPlot.PlotGraphics(line, title, xaxislabel, 'y axis')

        # Let 'er Rip!
        self.plotter.Draw(gc)
        self.isGraphPresent = True


        return

    def OnSearchQuery(self, event):
        """
        Method called when a user types a search query that will be
        applied to the loaded tree of esxtop metrics
        """
        if self.isDatasetLoaded:
            qstring = self.queryText.GetValue()
            if qstring == "":
                self.MyAlert("You entered a blank query!")
                return
            else:
                self._applyQuery(qstring,"ORANGE")
        else:
            self.MyAlert("You need to load a dataset first!")
        return

    def _applyQuery(self, regExString, color="BLUE"):
        """
        This Method actually does the regex search of the dataset and
        displays the new query
        """

        try:
            regExObject = re.compile(
                                     self._raw(regExString.rstrip('\n')),
                                     re.IGNORECASE|re.VERBOSE)
        except:
            self.MyAlert("Unrecognizable Regular Expression!")
            return
        query_display = (regExString.strip()).replace('\n',' ')
        #################################### HACK ALERT ################################
        # create a tree to hold the result set
        result_set_tree = esxp_datasource.HvTree('%%SearchResult%%')
        dlg = wx.ProgressDialog("Search Progress" , "",
                                 maximum =self.datavector.colmag,
                                 style=wx.PD_ELAPSED_TIME|wx.PD_AUTO_HIDE)

        if len(regExString) > MAXDisplayQueryLength:
            query_display = regExString[:MAXDisplayQueryLength] + "..."

        for j in xrange(self.datavector.colmag-1): # ugly, fix me
            if j % 100 ==0:
                    dlg.Update(j)
            # if no match go to the next one
            if regExObject.search(self.datavector.l[j]) == None:
                continue

            ### Apply the WHERE clause here if there is one ###

            # turn label into a list of path elements
            m = self.datavector.l[j].split('\\')
            m[2] = 'Query: ' + query_display
            # add the path into the t-node tree, truncating the
            # two null elements at the front of the list
            result_set_tree.addMetric([ m[k] for k in xrange (2, len(m))])
        if result_set_tree.isZero():
            self.MyAlert("Empty Result set for query:\n " + regExString)
        else:
            self.tree.merge(self.datavector, result_set_tree,color)
            dlg.Update(self.datavector.colmag)
            # save the query in case user wants to save favorites
            self.datavector.AddQueryString(regExString)
        dlg.Destroy()
        return

    def _raw(self,text):
        """Returns a raw string representation of text"""
    # this is a translation dictionary and function to fix the input
    # a user types into the area, this enables a user to "cut and paste"
    # regex right out of their egrep scripts and have it work without
    # fiddling with the expression itself
        escape_dict={'\a': r'\a',
               '\b': r'\b',
               '\c': r'\c',
               '\f': r'\f',
               '\n': r'\n',
               '\r': r'\r',
               '\t': r'\t',
               '\v': r'\v',
               '\'': r'\'',
               '\"': r'\"',
               '\0': r'\0',
               '\1': r'\1',
               '\2': r'\2',
               '\3': r'\3',
               '\4': r'\4',
               '\5': r'\5',
               '\6': r'\6',
               '\7': r'\7',
               '\8': r'\8',
               '\\': r'\\',
               '\9': r'\9'}


        new_string=''
        for char in text:
            try: new_string += escape_dict[char]
            except KeyError: new_string += char
        return new_string



    def OnRightClick(self, event):
        """
        Handle right-clicks on a selection, throw up a context menu with
        possible options
        """
        self.PopupMenu(MyPopupMenu(self), (-1, -1))
        return

    def OnCloseDataset(self, event):
        """
        Close the current dataset and attempt to release all of the created
        objects and data structures
        """
        if not self.isDatasetLoaded:
            self.MyAlert("No dataset is currently open!")
            return
        # might need to perform actions... see DataSource
        self.datavector = None
        # might need to perform actions ... see MyTreeCtrl
        self.tree.DeleteAllItems()
        self.plotter.Clear()
        self.isDatasetLoaded = False
        self.isGraphPresent = False



class MyHelpDialog(wx.Dialog):
    """
    A simple Dialog Widget that is used to display the preferences window
    """

    def __init__(self, html_page=""):
        wx.Dialog.__init__(self, None, -1, 'Help', size=(800, 500),
                           style=wx.CAPTION)
        okButton = wx.Button(self, wx.ID_OK, "OK", pos=(350, 445))
        okButton.SetDefault()

class MyPopupMenu(wx.Menu):
    def __init__(self, parent):
        wx.Menu.__init__(self)

        self.parent = parent

        delete = wx.MenuItem(self, wx.NewId(), 'Delete')
        self.AppendItem(delete)
        self.Bind(wx.EVT_MENU, self.OnDelete, id=delete.GetId())

        export = wx.MenuItem(self, wx.NewId(), 'Export')
        self.AppendItem(export)
        self.Bind(wx.EVT_MENU, self.OnExport, id=export.GetId())


    def OnDelete(self, event):
        if self.parent.MyDialog("Delete this branch?"):
            itemlist = self.parent.tree.GetSelections()
            if len(itemlist) == 0:                  #no selections were made
                return

            if len(itemlist) > 1:         #too many selections were made
                self.parent.MyAlert("You can only right click on a "
                                    "single selection")
                return
            self.parent.tree.DeleteChildren(itemlist[0])
            self.parent.tree.Delete(itemlist[0])
        else:
            return

    def OnExport(self, event):
        self.parent.OnExportColumns(None)
        return