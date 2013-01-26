/*
Copyright 2012 Jeff Trull <jetrull@sbcglobal.net>

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/  
public with sharing class SlickbackRemotingCtrl {
	// for now, we simply forward these calls to the methods worked out previously for ExtJS
	// having this indirection gives us the ability to alter return types on the fly, provide
	// additional methods, etc. that work better for Slickback.

	@RemoteAction
	public static ExtJSStoreRemotingCtrl.CRUDResponse
	query(ExtJSStoreRemotingCtrl.QueryObj qobj) {
		// forward request to existing ExtJS controller
		// TODO: refactor into separate class
		return ExtJSStoreRemotingCtrl.query(qobj);
	}

	@RemoteAction
	public static ExtJSStoreRemotingCtrl.CRUDResponse
	updat(ExtJSStoreRemotingCtrl.CRUDData dat) {
		return ExtJSStoreRemotingCtrl.updat(dat);
	}

	@RemoteAction
    public static List<ExtJSStoreRemotingCtrl.FieldInfo>
    describeFields(String objName,
                   List<String> fieldNames) {
    	// forward
    	return ExtJSStoreRemotingCtrl.describeFields(objName, fieldNames);	
    }
}