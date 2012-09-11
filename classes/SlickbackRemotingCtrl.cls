public with sharing class SlickbackRemotingCtrl {
	@RemoteAction
	public static List<Contact>
	query() {
		// For now, mindlessly return all contacts and a fixed set of fields
		return [SELECT Id,FirstName,LastName,Birthdate,Email,Level__c FROM Contact];
	}
}