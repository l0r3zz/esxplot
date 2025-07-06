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
        # Call parent constructor first
        super(MyPlotCanvas, self).__init__(parent, id, pos, size, style, name)
        
        # Initialize custom attributes
        self.isWindows = False
        self.defDir = ""
        
        # Use our own state for drawing the zoom box to avoid interfering
        # with the parent class's internal state (_zoomCorner1).
        self._zoomBoxCorner1_client = None

    def OnMouseLeftDown(self, event):
        # This method is now an override, not a new binding.
        if self.enableZoom:
            # Store the start of the zoom box in client coordinates.
            self._zoomBoxCorner1_client = event.GetPosition()
        
        # IMPORTANT: Call the parent's method to ensure its logic runs.
        super(MyPlotCanvas, self).OnMouseLeftDown(event)

    def OnMotion(self, event):
        # If we are in the middle of a zoom drag, draw our custom box.
        if event.Dragging() and event.LeftIsDown() and self.enableZoom and self._zoomBoxCorner1_client is not None:
            self._drawZoomBox(self._zoomBoxCorner1_client, event.GetPosition())
        
        # IMPORTANT: Call the parent's method to ensure its logic runs.
        super(MyPlotCanvas, self).OnMotion(event)

    def OnMouseLeftUp(self, event):
        if self._zoomBoxCorner1_client is not None:
            # Reset our zoom box state.
            self._zoomBoxCorner1_client = None
            # Redraw to ensure the last drawn box is erased. The parent's
            # final zoom action will also cause a redraw, but this is safer.
            self.Redraw()
            
        # IMPORTANT: Call the parent's method to perform the actual zoom.
        super(MyPlotCanvas, self).OnMouseLeftUp(event)

    def _drawZoomBox(self, corner1, corner2):
        """Draws the zoom box on the canvas using client coordinates."""
        # Redraw the plot from the buffer to erase any previous box.
        self.Redraw()
        self.Update()

        dc = wx.ClientDC(self)
        pen_color = getattr(self, 'zoomColor', 'RED')
        pen_width = getattr(self, 'zoomWidth', 1)
        style_map = {
            'SOLID': wx.PENSTYLE_SOLID,
            'DOTTED': wx.PENSTYLE_DOT,
            'DOT-DASH': wx.PENSTYLE_DOT_DASH,
            'DASHED': wx.PENSTYLE_SHORT_DASH,
        }
        pen_style_str = getattr(self, 'zoomLine', 'DOTTED')
        pen_style = style_map.get(pen_style_str, wx.PENSTYLE_DOT)

        pen = wx.Pen(pen_color, pen_width, pen_style)
        dc.SetPen(pen)
        dc.SetBrush(wx.TRANSPARENT_BRUSH)
        dc.SetLogicalFunction(wx.COPY)

        rect = wx.Rect(corner1, corner2)
        dc.DrawRectangle(rect)

    def SetOS(self, windowsP):
        self.isWindows = windowsP

    def SaveFile(self, fileName=''):
        """Saves the plot to a file based on extension."""
        wildcard = (
            "PNG files (*.png)|*.png|"
            "JPEG files (*.jpg;*.jpeg)|*.jpg;*.jpeg|"
            "BMP files (*.bmp)|*.bmp|"
            "XBM files (*.xbm)|*.xbm|"
            "XPM files (*.xpm)|*.xpm"
        )

        if not fileName:
            with wx.FileDialog(
                self, "Save plot as...",
                defaultDir=self.defDir,
                wildcard=wildcard,
                style=wx.FD_SAVE | wx.FD_OVERWRITE_PROMPT
            ) as dlg:
                if dlg.ShowModal() != wx.ID_OK:
                    return False
                fileName = dlg.GetPath()
                self.defDir = dlg.GetDirectory()

        ext = fileName.split('.')[-1].lower()
        bmp_type_map = {
            'png': wx.BITMAP_TYPE_PNG,
            'jpg': wx.BITMAP_TYPE_JPEG,
            'jpeg': wx.BITMAP_TYPE_JPEG,
            'bmp': wx.BITMAP_TYPE_BMP,
            'xbm': wx.BITMAP_TYPE_XBM,
            'xpm': wx.BITMAP_TYPE_XPM,
        }

        if ext not in bmp_type_map:
            wx.MessageBox(f"Unsupported file type: '.{ext}'", "Save Error", wx.OK | wx.ICON_ERROR)
            return False

        return self._Buffer.SaveFile(fileName, bmp_type_map[ext])
