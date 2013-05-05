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

@isTest
private class TestExtJSStoreRemotingCtrl {

    static testMethod void dataAccessTest() {
        // create some data for use with the paging code
        // let's name contacts with sequential letters from Aaa to Dzz
        // that will give 3*26^2 or a bit over 2,000 names, which is enough to test OFFSET
        ExtJSStoreRemotingCtrl.CRUDData testRecords = new ExtJSStoreRemotingCtrl.CRUDData();
        testRecords.sobjname = 'Contact';
        testRecords.fields = 'FirstName,LastName,Birthdate';
        testRecords.records = new List<Map<String, String>>();
        for (Integer c1 = 0; c1 < 3; ++c1) {
            for (Integer c2 = 0; c2 < 26; ++c2) {
                for (Integer c3 = 0; c3 < 26; ++c3) {
                    // offset characters so we have a capitalized firstname, lowercase last
                    String firstname = String.fromCharArray(new List<Integer>{c1+65, c2+97, c3+97});
                    testRecords.records.add(new Map<String, String>{'FirstName' => firstname,
                                                                    'LastName' => 'Fakename'});
                }
            }
        }
        Test.startTest();

        // ensure we can create the records
        ExtJSStoreRemotingCtrl.CRUDResponse cresp = ExtJSStoreRemotingCtrl.create(testRecords);
        System.assert(cresp.success);
        System.assertEquals(3*26*26, cresp.records.size());

        // now read them back with variations, to check paging
        ExtJSStoreRemotingCtrl.QueryObj q = new ExtJSStoreRemotingCtrl.QueryObj();
        q.sobjname = 'Contact';
        q.fields = 'Id,FirstName,LastName';

        // basic query: request a small number of records, no special parameters
        q.start = 0;
        q.recordCount = 3;
        ExtJSStoreRemotingCtrl.CRUDResponse basicresp = ExtJSStoreRemotingCtrl.query(q);

        // sorted query: ask for a different number of records and sort by firstname
        q.sortParams = new List<Map<String, String>>();
        q.sortParams.add(new Map<String, String>{'property' => 'FirstName', 'direction' => 'DESC'});
        q.start = 3;         // skip first three results
        q.recordCount = 6;
        ExtJSStoreRemotingCtrl.CRUDResponse dsortedresp = ExtJSStoreRemotingCtrl.query(q);

        // sorted ascending query
        q.sortParams[0].put('direction', 'ASC');
        ExtJSStoreRemotingCtrl.CRUDResponse asortedresp = ExtJSStoreRemotingCtrl.query(q);      

        // request data at the OFFSET limit
        q.start = 2000;
        ExtJSStoreRemotingCtrl.CRUDResponse atlimitresp = ExtJSStoreRemotingCtrl.query(q);      
        
        // and past the OFFSET limit
        q.start = 2001;
        ExtJSStoreRemotingCtrl.CRUDResponse pastlimitresp = ExtJSStoreRemotingCtrl.query(q);        

        // a large (greater than SOQL iteration batch size) request, with OFFSET
        q.start = 1819;      // 2027 - 8*26 for convenience
        q.recordCount = 205;
        ExtJSStoreRemotingCtrl.CRUDResponse largeresp = ExtJSStoreRemotingCtrl.query(q);        

        // Now make some changes to the data
        // Modify the LastName of the records returned in the second query
        ExtJSStoreRemotingCtrl.CRUDData changedRecords = new ExtJSStoreRemotingCtrl.CRUDData();
        changedRecords.sobjname = 'Contact';
        changedRecords.fields = 'Id,LastName';
        changedRecords.records = new List<Map<String, String>>();
        for (SObject sobj : dsortedresp.records) {
            changedRecords.records.add(new Map<String, String>{'Id' => (String)sobj.get('Id'),
                                                               'LastName' => 'Updatedname'});
        }       
        ExtJSStoreRemotingCtrl.CRUDResponse changeresp = ExtJSStoreRemotingCtrl.updat(changedRecords);

        // Delete the records found by the ascending sorted query (Aad-Aai)
        ExtJSStoreRemotingCtrl.CRUDData deletedRecords = new ExtJSStoreRemotingCtrl.CRUDData();
        deletedRecords.sobjname = 'Contact';
        deletedRecords.fields = 'Id,LastName';
        deletedRecords.records = new List<Map<String, String>>();
        for (SObject sobj : asortedresp.records) {
            deletedRecords.records.add(new Map<String, String>{'Id' => (String)sobj.get('Id')});  // only Id needed
        }
        ExtJSStoreRemotingCtrl.CRUDResponse delresp = ExtJSStoreRemotingCtrl.delet(deletedRecords);     

        Test.stopTest();

        // basic result
        System.assert(basicresp.success);                  // it worked
        System.assertEquals(3*26*26, basicresp.total);     // the total count of records is what we inserted above
        System.assertEquals(3, basicresp.records.size());  // three records actually returned to us

        // descending sorted result
        System.assert(dsortedresp.success);
        System.assertEquals(3*26*26, dsortedresp.total);
        System.assertEquals(6, dsortedresp.records.size());
        System.assertEquals('Czw', dsortedresp.records[0].get('FirstName'));  // first three are Czz, Czy, Czx - skipped

        // ascending sorted result
        System.assert(asortedresp.success);
        System.assertEquals(3*26*26, asortedresp.total);
        System.assertEquals(6, asortedresp.records.size());
        System.assertEquals('Aad', asortedresp.records[0].get('FirstName'));  // first three are Aaa, Aab, Aac
        
        // starting at OFFSET limit result
        System.assert(atlimitresp.success);
        System.assertEquals(3*26*26, atlimitresp.total);
        System.assertEquals(6, atlimitresp.records.size());
        // last record (2027) in ascending order is Czz, so 26 before is Cyz and 2000 must be:
        System.assertEquals('Cyy', atlimitresp.records[0].get('FirstName'));

        // one past OFFSET limit result
        System.assert(pastlimitresp.success);
        System.assertEquals(3*26*26, pastlimitresp.total);
        System.assertEquals(6, pastlimitresp.records.size());
        System.assertEquals('Cyz', pastlimitresp.records[0].get('FirstName'));

        // large query
        System.assert(largeresp.success);
        System.assertEquals(3*26*26, largeresp.total);
        System.assertEquals(205, largeresp.records.size());
        System.assertEquals('Crz', largeresp.records[0].get('FirstName'));

        // update method test
        System.assert(changeresp.success);
        Integer updatedCount = [SELECT COUNT() FROM Contact WHERE LastName = 'Updatedname'];
        System.assertEquals(6, updatedCount);

        // delete method test
        System.assert(delresp.success);
        Integer totalCount = [SELECT COUNT() FROM Contact];
        System.assertEquals(3*26*26-6, totalCount);   // initial total with 6 removed
    }

    static testMethod void describeTest() {
        // check only standard objects, so no setup is required
        Test.startTest();
        List<ExtJSStoreRemotingCtrl.FieldInfo> ctFields =
            ExtJSStoreRemotingCtrl.describeFields('Contact',
                                                  new List<String>{'Id', 'CreatedDate', 'Birthdate'});
        List<ExtJSStoreRemotingCtrl.FieldInfo> accFields =
            ExtJSStoreRemotingCtrl.describeFields('Account',
                                                  new List<String>{'NumberOfEmployees', 'Industry'});
        List<ExtJSStoreRemotingCtrl.FieldInfo> userFields =
            ExtJSStoreRemotingCtrl.describeFields('User',
                                                  new List<String>{'IsActive'});
        Test.stopTest();

        System.assertEquals('Id', ctFields[0].name);
        System.assert(!ctFields[0].modifiable);
        System.assertEquals('id', ctFields[0].fieldType);
        System.assertEquals('Contact ID', ctFields[0].label);

        System.assertEquals('CreatedDate', ctFields[1].name);
        System.assert(!ctFields[1].modifiable);
        System.assertEquals('datetime', ctFields[1].fieldType);
        System.assertEquals('Created Date', ctFields[1].label);

        System.assertEquals('Birthdate', ctFields[2].name);
        System.assert(ctFields[2].modifiable);
        System.assertEquals('date', ctFields[2].fieldType);
        System.assertEquals('Birthdate', ctFields[2].label);

        System.assertEquals('NumberOfEmployees', accFields[0].name);
        System.assert(accFields[0].modifiable);
        System.assertEquals('integer', accFields[0].fieldType);
        System.assertEquals('Employees', accFields[0].label);

        System.assertEquals('Industry', accFields[1].name);
        System.assert(accFields[1].modifiable);
        System.assertEquals('picklist', accFields[1].fieldType);
        System.assertEquals('Industry', accFields[1].label);

        System.assertEquals('IsActive', userFields[0].name);
        System.assert(userFields[0].modifiable);
        System.assertEquals('boolean', userFields[0].fieldType);
        System.assertEquals('Active', userFields[0].label);
    }

}