#!/usr/bin/env python

# Produce the VimService_client.py and VimService_types.py with
#     wsdl2py -l -b  vimService.wsdl


'''
File:vSSDK.py A vSphere 4 SDK toolkit for Python
Based on a file posted by Werner Still of Hitachi Data Systems GmbH

Created on Dec 24, 2009

@author: Geoff White
'''

__svnid__ = '$Id: $'
copyright = """
(c)Copyright 2009,2010 Geoff White

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

import sys
import logging
from VimService_types import *
from VimService_client import *

from optparse import OptionParser

class VMwareVI_Error(Exception):
    """
    Exception VMwareVI_Error

    This exception is used in VMwareVI Errors
    """
    
    def __init__(self, methodName):
        Exception.__init__(self)
        self.__methodName = methodName

    def __str__(self):
        return "VMwareVI Error in " + str(self.__methodName)
        
class VMwareVI_NonViError(Exception):
    """
    Exception VMwareVI Error not issued by Vi
    """
    def __init__(self, methodName):
        Exception.__init__(self)
        self.__methodName = methodName
    
    def __str__(self):
        return "VMwareVI NonVI Error in " + str(self.__methodName)




class VMwareVI:
    """
    This class is the main entry point into VMware VI SOAP
    The creator connects to the VMware ESX or Virtual Center
    All other Members use this connection
    """
    ServiceContent = None
    PropertyCollector = None
    rootFolder = None
    proxy = None
    indent = 0


    def __init__(self, Host=None, UserName=None, Password=None, Trace=None):
        """
        Create the necessary Communication interfaces, get the ServiceInstance and log on
        """
        Location = "en"
        try:
            loc = VimServiceLocator()
            # Check if the Host Variable starts with the protocol. If not add https
            if Host == None:
                ConnectString = Host
            elif Host.startswith('https://') or Host.startswith('http://'):
                ConnectString = Host
            else:
                ConnectString = "https://%s/sdk" % (Host)
            if Trace == None:
                self.proxy = loc.getVimPort(url = ConnectString)
            else:
                self.proxy = loc.getVimPort(url = ConnectString, tracefile = Trace)

            # RetrieveServiceContent
            RetrieveServiceContentRequest = RetrieveServiceContentRequestMsg()
            # Now create the content of the RetreiveServiceContent Request. This is a ManagedObjectReference
            # The Parameter is the Instance that is needed. In this case a ServiceInstance
            Element = RetrieveServiceContentRequest.new__this("ServiceInstance")
            # The ManagedObjectReference needs to tell the VMware VI what type it requests. This works with
            # the attribute type. Here for RetreiveServiceContent it is a type ServiceInstance.
            Element.set_attribute_type("ServiceInstance")
            RetrieveServiceContentRequest.set_element__this(Element)
            self.ServiceContent = self.proxy.RetrieveServiceContent(RetrieveServiceContentRequest)._returnval
            logging.debug("RetrieveServiceContent: response.About.FullName = %s" % (self.ServiceContent.About.FullName))
            logging.debug("RetrieveServiceContent: response.SessionManager = %s" % (self.ServiceContent.SessionManager))
            sessionManager = str(self.ServiceContent.SessionManager)
            self.PropertyCollector = str(self.ServiceContent.PropertyCollector)
            self.rootFolder = self.ServiceContent.RootFolder
            RetrieveServiceContentRequest = None
        except (ns0.RuntimeFault_Def), e:
            #raise(VMwareVI_Error("VMwareVI.__init__ %s: %s" % (e, e.value)))
            raise(VMwareVI_Error("VMwareVI.__init__ %s" % (e)))
        except Exception, e:
            raise(VMwareVI_NonViError("VMwareVI.__init__ %s" % (e)))

        try:
            # Login
            LoginRequest = LoginRequestMsg()
            This = LoginRequest.new__this(sessionManager)
            This.set_attribute_type("SessionManager")
            LoginRequest.set_element__this(This)
            LoginRequest.set_element_userName(UserName)
            LoginRequest.set_element_password(Password)
            LoginRequest.set_element_locale(Location)
            LoginResponse = self.proxy.Login(LoginRequest)._returnval
            LoginRequest = None
            logging.debug("Login: response.FullName = %s" % (LoginResponse.FullName))
            logging.debug("Login: response.Key = %s" % (LoginResponse.Key))
            logging.debug("Login: response.UserName = %s" % (LoginResponse.UserName))
            LoginResponse = None
        except (ns0.InvalidLoginFault, ns0.InvalidLocaleFault, ns0.RuntimeFault), e:
            raise(VMwareVI_Error("VMwareVI.__init__ %s" % (e)))
        except Exception, e:
            raise(VMwareVI_NonViError("VMwareVI.__init__ %s" % (e)))

    def CurrentTime(self):
        # CurrentTime
        CurrentTimeRequest = CurrentTimeRequestMsg()
        This = CurrentTimeRequest.new__this("ServiceInstance")
        This.set_attribute_type("ServiceInstance")
        CurrentTimeRequest.set_element__this(This)
        CurrentTimeResponse = self.proxy.CurrentTime(CurrentTimeRequest)._returnval
        CurrentTimeResponseString = str(CurrentTimeResponse)
        logging.debug("CurrentTime: %s" % (CurrentTimeResponseString))
        CurrentTimeRequest = None
        CurrentTimeResponse = None
        return CurrentTimeResponseString

    # RetreiveProperties
    def RetrieveProperties(self, propSetType=None, objectSetObj=None, AllElements=False):
        try:
            PropertiesRequest = RetrievePropertiesRequestMsg()
            Element = PropertiesRequest.new__this(self.PropertyCollector)
            Element.set_attribute_type("PropertyCollector")
            PropertiesRequest.set_element__this(Element)

            # We need the SpecSet Element here to get the other new() Functions
            SpecSet_PropertyFilterSpec = PropertiesRequest.new_specSet()

            if (propSetType == None):
                propSetType = "ManagedEntity"
            PropSetArray = []
            PropSet = SpecSet_PropertyFilterSpec.new_propSet()
            PropSet.set_element_type(propSetType)
            PropSet.set_element_all(AllElements)
            PropSet.set_element_pathSet(["name"])
            PropSetArray.append(PropSet)


            if objectSetObj == None:
                objectSetObj = self.rootFolder
            ObjectSetArray = []
            ObjectSet = SpecSet_PropertyFilterSpec.new_objectSet()
            ObjectSet.set_element_obj(objectSetObj)
            ObjectSet.set_element_skip(False)
            # Add the Traversal Part of the RetrieveProperties
            resourcePoolTraversal = ns0.TraversalSpec_Def("resourcePoolTraversalSpec").pyclass()
            resourcePoolTraversal.set_element_name("resourcePoolTraversalSpec")
            resourcePoolTraversal.set_element_type("ResourcePool")
            resourcePoolTraversal.set_element_path("resourcePool")
            resourcePoolTraversal.set_element_skip(False)
            SPCAresourcePool = []
            SPCAresourcePool.append(ObjectSet.new_selectSet())
            SPCAresourcePool[0].set_element_name("resourcePoolTraversalSpec")
            resourcePoolTraversal.set_element_selectSet(SPCAresourcePool)

            computeResourceRpTraversal = ns0.TraversalSpec_Def("computeResourceRpTraversalSpec").pyclass()
            computeResourceRpTraversal.set_element_name("computeResourceRpTraversalSpec")
            computeResourceRpTraversal.set_element_type("ComputeResource")
            computeResourceRpTraversal.set_element_path("resourcePool")
            computeResourceRpTraversal.set_element_skip(False)
            SPCAcomputeResourceRp = []
            SPCAcomputeResourceRp.append(ObjectSet.new_selectSet())
            SPCAcomputeResourceRp[0].set_element_name("computeResourceRpTraversalSpec")
            computeResourceRpTraversal.set_element_selectSet(SPCAcomputeResourceRp)

            computeResourceHostTraversal = ns0.TraversalSpec_Def("computeResourceHostTraversalSpec").pyclass()
            computeResourceHostTraversal.set_element_name("computeResourceHostTraversalSpec")
            computeResourceHostTraversal.set_element_type("ComputeResource")
            computeResourceHostTraversal.set_element_path("host")
            computeResourceHostTraversal.set_element_skip(False)

            datacenterHostTraversal = ns0.TraversalSpec_Def("datacenterHostTraversalSpec").pyclass()
            datacenterHostTraversal.set_element_name("datacenterHostTraversalSpec")
            datacenterHostTraversal.set_element_type("Datacenter")
            datacenterHostTraversal.set_element_path("hostFolder")
            datacenterHostTraversal.set_element_skip(False)
            SPCAdatacenterHost = []
            SPCAdatacenterHost.append(ObjectSet.new_selectSet())
            SPCAdatacenterHost[0].set_element_name("folderTraversalSpec")
            datacenterHostTraversal.set_element_selectSet(SPCAdatacenterHost)

            datacenterVmTraversal = ns0.TraversalSpec_Def("datacenterVmTraversalSpec").pyclass()
            datacenterVmTraversal.set_element_name("datacenterVmTraversalSpec")
            datacenterVmTraversal.set_element_type("Datacenter")
            datacenterVmTraversal.set_element_path("hostFolder")
            datacenterVmTraversal.set_element_skip(False)
            SPCAdatacenterVm = []
            SPCAdatacenterVm.append(ObjectSet.new_selectSet())
            SPCAdatacenterVm[0].set_element_name("folderTraversalSpec")
            datacenterVmTraversal.set_element_selectSet(SPCAdatacenterVm)

            folderTraversal = ns0.TraversalSpec_Def("resourcePoolTraversalSpec").pyclass()
            folderTraversal.set_element_name("folderTraversalSpec")
            folderTraversal.set_element_type("Folder")
            folderTraversal.set_element_path("childEntity")
            folderTraversal.set_element_skip(False)
            SPCAfolder = []
            SPCAfolder.append(ObjectSet.new_selectSet())
            SPCAfolder[0].set_element_name("folderTraversalSpec")
            # Add here all the other elements
            SPCAfolder.append(datacenterHostTraversal)
            SPCAfolder.append(datacenterVmTraversal)
            SPCAfolder.append(computeResourceRpTraversal)
            SPCAfolder.append(computeResourceHostTraversal)
            SPCAfolder.append(resourcePoolTraversal)
            folderTraversal.set_element_selectSet(SPCAfolder)

            SelectionSpecArray = []
            SelectionSpecArray.append(folderTraversal)
            ObjectSet.set_element_selectSet(SelectionSpecArray)
            ObjectSetArray.append(ObjectSet)

            SpecSetArray = []
            SpecSet_PropertyFilterSpec.set_element_propSet(PropSetArray)
            SpecSet_PropertyFilterSpec.set_element_objectSet(ObjectSetArray)
            SpecSetArray.append(SpecSet_PropertyFilterSpec)
            PropertiesRequest.set_element_specSet(SpecSetArray)

            PropertiesResponse = self.proxy.RetrieveProperties(PropertiesRequest)
            return PropertiesResponse.Returnval
        except (ns0.InvalidPropertyFault_Dec, ns0.RuntimeFault_Def), e:
            raise(VMwareVI_Error("VMwareVI.RetrieveProperties %s" % (e)))
        except Exception, e:
            raise(VMwareVI_NonViError("VMwareVI.RetrieveProperties %s" % (e)))


    def Logout(self):
        # Logout
        try:
            LogoutRequest = LogoutRequestMsg()
            sessionManager = str(self.ServiceContent.SessionManager)
            This = LogoutRequest.new__this(sessionManager)
            This.set_attribute_type("SessionManager")
            LogoutRequest.set_element__this(This)
            LogoutResponse = self.proxy.Logout(LogoutRequest)
        except (ns0.RuntimeFault), e:
            raise(VMwareVI_Error("VMwareVI.Logout %s" % (e)))
        except Exception, e:
            raise(VMwareVI_NonViError("VMwareVI.Logout %s" % (e)))

    def printInventory(self, ObjectContentArray):
        if ObjectContentArray == None:
            print("No Managed Entities retrieved!")
        else:
            for ObjectContent in ObjectContentArray:
                ManagedObjectReference = ObjectContent.get_element_obj()
                DynamicPropertyArray = ObjectContent.get_element_propSet()
                print("Object Type: " + ManagedObjectReference.get_attribute_type())
                print("Reference Value: " + ManagedObjectReference )

                if DynamicPropertyArray != None:
                    for DynamicProperty in DynamicPropertyArray:
                        if (DynamicProperty != None):
                            print("  Property Name: " + DynamicProperty.get_element_name())
                            if (type(DynamicProperty) == []): # We have here an array
                                ObjectArray = DynamicProperty.get_element_val()
                                for Object in ObjectArray:
                                    print("Object: " + Object)
                            else:
                                print("  Property Value: " + DynamicProperty.get_element_val())

if __name__ == '__main__':
    parser = OptionParser()
    parser.add_option("-c", "--HostName", dest="Host",
                      help="Hostname to connect", default="localhost")
    parser.add_option("-u", "--UserName", dest="UserName",
                      help="Username to Login", default="adm")
    parser.add_option("-p", "--Password", dest="Password",
                      help="Password to Login", default="vmware")
    parser.add_option("-d", "--Debug", dest="Debug", action="store_true",
                      help="Enable Debug", default=False)
    parser.add_option("-f", "--DebugFile", dest="DebugFile",
                      help="File for Debug", metavar="FILE", default="stderr")

    (options, args) = parser.parse_args()

    Trace=None
    if (options.Debug):
        if options.DebugFile == 'stderr':
            Trace=sys.stderr
        else:
            Trace=open(options.DebugFile, 'w')
    try:
        vi = VMwareVI(options.Host, options.UserName, options.Password, Trace=Trace)
    except Exception, e:
        print("Error initializing connection to %s %s:%s" % (options.Host,
                                                             options.UserName,
                                                             options.Password))
        print("Error content %s" % (str(e)))
        sys.exit(1)
    try:
        CurrentTime = vi.CurrentTime()
        print("Current Time = %s" % (CurrentTime))
    except Exception, e:
        print("Error retrieving Current Time")
        print("Error content %s" % (str(e)))
    try:
        HS = vi.RetrieveProperties(propSetType="ManagedEntity",
                                   objectSetObj=None, AllElements=False)
        # to have here the second call to RetrieveProperties will lead to an Error in
        # ZSI 2.0 described on the top of the file
        #HS = vi.RetrieveProperties(propSetType="ManagedEntity",
        #                           objectSetObj=None, AllElements=False)
        vi.printInventory(HS)
    except Exception, e:
        print("Error retrieving Properties")
        print("Error content %s" % (str(e)))
    try:
        vi.Logout()
    except Exception, e:
        print("Error Logout")
        print("Error content %s" % (str(e)))

