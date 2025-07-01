#!/usr/bin/env python

__svnid__ = '$Id: $'
copyright = """
(c)Copyright 2011 Geoff White

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

import wx
import wx.lib.plot as wxPlot
import string as _string



############################## HACK ALERT ###############################
class MyTreeCtrl(wx.TreeCtrl): ### candidate for refactoring for 1.1
    '''This customized TreeCtrl class has the __init__ subclassed to
    do the heavy lifting, also merge for integrating the results of
    a regex query into the treectrl, and a custom method (MyCollapse)
    to collapse the tree if it's expanded.
    '''

    def __init__(self, parent, iid, position, size, style):
        '''Load up the TreeCntrl data structure with information from
        our very own 'tnode' DB
        '''
        # Call parent constructor
        wx.TreeCtrl.__init__(self, parent, iid, position, size, style)
        return

    def MyTreeLoad(self,v):
        """
        Use this to build the initial GUI tree from the loaded dataset,
        essentially a merge into an empty root tree
        """
        self.csvl = v
        self.tnodeDB = self.csvl.dRoot.root_node
        self.root = self.AddRoot(self.tnodeDB[0])
        self.merge(v,v.dRoot,color='BLACK')
        return
######################### HACK ALERT ###############################
# Right now this routine is used to brut force the entire dataset into the Window System's
# TreeControl wdget, very ugly, slow and wasteful. What needs to happen is that the initial
# load should just load the root and the top level parts from the pytrie structure, and additional
# elements of the tree are "merged" as user clicks

    def merge(self,cslv,merge_root,color="ORANGE"):
        """
        Take one T-node branch and merge it into a 'root"
        This routine will need to be modified when we have multiple
        data sets to support
        """

        mergeDB = merge_root.root_node
        self.MyCollapse()   #Collapse the tree control GUI
        first = []
        second = []
        third = []

        for inode in mergeDB[1]:
            first.append(self.AppendItem(self.root,inode[0] ))
            self.SetItemTextColour(first[-1],color)
            for jnode in inode[1] :
                second.append(self.AppendItem(first[-1],jnode[0]))
                # we're going to count the columns that are all zero
                # and if all of the elements under this heading are empty...
                ctr =0
                zero_ctr = 0
                for knode in jnode[1] :
                    ctr +=1
                    third.append(self.AppendItem(second[-1],knode[0]))
                    # we're at the leaf, set the column index
                    self.SetItemData(third[-1],knode[1][0])
                    # if the data is all zeros, set the color to light blue
                    if cslv.IsColZero(int(knode[1][0])):
                        self.SetItemTextColour(third[-1],'GREY')
                        zero_ctr +=1
                # set the heading to grey to signal, lapse(self):
                if ctr == zero_ctr:
                    self.SetItemTextColour(second[-1],'GREY')
        return


    def MyCollapse(self):
        """
        Walk the tree and collapse it visually so that the user can
        clearly see the Query branches when they are added
        """
        root_item = self.GetRootItem()
        (child, cookie) = self.GetFirstChild(root_item)  #get the first child
        if not child.IsOk():
            return
        self.Collapse(child)
        while child:
            (child, cookie) = self.GetNextChild(root_item, cookie)
            if not child.IsOk() :
                break
            self.Collapse(child)
        return

    def MyTreeLeafList(self,item):
        """
         Given an item in a wxTreeCtrl control, create a list
         of the leaves.
        """
        res = []
        chlditem = self.GetFirstChild(item)[0]
        if chlditem.IsOk():
            res.extend(self.MyTreeLeafList(chlditem))
        else:
            return [item]
        while chlditem.IsOk() :
            res.extend(self.MyTreeLeafList(chlditem))
            chlditem = self.GetNextSibling(chlditem)
        return res



class MyPlotCanvas(wxPlot.PlotCanvas):
    def __init__(self, parent, id=-1, pos=wx.Point(-1, -1),
                 size=wx.Size(-1, -1), style=0, name='plotCanvas'):
        self.isWindows = False
        self.defDir = ""
        wxPlot.PlotCanvas.__init__(self, parent, id, pos, size, style, name)


    def OnLeave(self,event):
        # place holder for code to handle LEAVE_WINDOW and
        # send Left-MouseButton-Up
        if (self.isWindows and  event.LeftIsDown()) :
            # try to return the up event when leaving
            wxPlot.PlotCanvas.OnMouseLeftUp(self,event)
        # call the superclass method I just overode
        wxPlot.PlotCanvas.OnLeave(self,event)


    def SetOS(self,windowsP):
        self.isWindows = windowsP

    def SaveFile(self,fileName= ''):
        """Saves the file to the type specified in the extension. If no file
        name is specified a dialog box is provided.  Returns True if sucessful,
        otherwise False.

        .bmp  Save a Windows bitmap file.
        .xbm  Save an X bitmap file.
        .xpm  Save an XPM bitmap file.
        .png  Save a Portable Network Graphics file.
        .jpg  Save a Joint Photographic Experts Group file.
        """
        extensions = {
            "bmp": wx.BITMAP_TYPE_BMP,       # Save a Windows bitmap file.
            "xbm": wx.BITMAP_TYPE_XBM,       # Save an X bitmap file.
            "xpm": wx.BITMAP_TYPE_XPM,       # Save an XPM bitmap file.
            "jpg": wx.BITMAP_TYPE_JPEG,      # Save a JPG file.
            "png": wx.BITMAP_TYPE_PNG,       # Save a PNG file.
            }

        fType = _string.lower(fileName[-3:])
        dlg1 = None
        while fType not in extensions:

            if dlg1:                  # FileDialog exists: Check for extension
                dlg2 = wx.MessageDialog(self, 'File name extension\n'
                'must be one of\nbmp, xbm, xpm, png, or jpg',
                'File Name Error', wx.OK | wx.ICON_ERROR)
                try:
                    dlg2.ShowModal()
                finally:
                    dlg2.Destroy()
            else:                     # FileDialog doesn't exist: just check one
                dlg1 = wx.FileDialog(
                    self,
                    ("Choose a file with extension bmp, gif, xbm,"
                     " xpm, png, or jpg"),
                     self.defDir, "",
                    ("BMP files (*.bmp)|*.bmp|XBM files (*.xbm)|*.xbm|XPM"
                     " file (*.xpm)|*.xpm|PNG files (*.png)|*.pnga"
                     "|JPG files (*.jpg)|*.jpg"),
                    style=wx.SAVE|wx.OVERWRITE_PROMPT
                    )

            if dlg1.ShowModal() == wx.ID_OK:
                fileName = dlg1.GetPath()
                self.defDir = dlg1.GetDirectory()
                fType = _string.lower(fileName[-3:])
            else:                      # exit without saving
                dlg1.Destroy()
                return False

        dlg1.Destroy()

        # Save Bitmap
        res= self._Buffer.SaveFile(fileName, extensions[fType])
        return res



