#!/usr/bin/env python
# Test script for SDK connection
import sys
from VimService_client import *

if len(sys.argv) > 1 :
	host = sys.argv[1]
else:
	host ="10.100.101.46"

ConnectString = "https://%s/sdk" % (host)
locator = VimServiceLocator()
proxy = locator.getVimPort(ConnectString)
RetrieveServiceContentRequest = RetrieveServiceContentRequestMsg()
Element = RetrieveServiceContentRequest.new__this("ServiceInstance")
Element.set_attribute_type("ServiceInstance")
RetrieveServiceContentRequest.set_element__this(Element)
ServiceContent = proxy.RetrieveServiceContent(RetrieveServiceContentRequest)._returnval
sessionManager = str(ServiceContent.SessionManager)
PropertyCollector = str(ServiceContent.PropertyCollector)
rootFolder = ServiceContent.RootFolder
RetrieveServiceContentRequest = None
# Login
LoginRequest = LoginRequestMsg()
#LoginRequest._this = LoginRequest.new__this(sessionManager)
#LoginRequest._this.set_attribute_type("SessionManager")
This = LoginRequest.new__this(sessionManager)
This.set_attribute_type("SessionManager")
LoginRequest.set_element__this(This)
LoginRequest.set_element_userName('root')
LoginRequest.set_element_password('vmware')
LoginRequest.set_element_locale("en")
LoginResponse = proxy.Login(LoginRequest)._returnval
CurrentTimeRequest = CurrentTimeRequestMsg()
This = CurrentTimeRequest.new__this("ServiceInstance")
This.set_attribute_type("ServiceInstance")
CurrentTimeRequest.set_element__this(This)
CurrentTimeResponse = proxy.CurrentTime(CurrentTimeRequest)._returnval
CurrentTimeResponseString = str(CurrentTimeResponse)
print("Ready >",CurrentTimeResponseString)
