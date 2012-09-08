A collection of examples for using ExtJS widgets with Salesforce.com data as a back end.

To use these, you need to create and upload an ExtJS "resource", which is just a zip file containing the ExtJS distribution.  You can remove any unneeded parts (samples, documentation) before uploading to your org. Name the resource ExtJS and update the version numbers in the components as needed to reflect the version of Ext you are actually using.

You'll need to upload the latest version of ExtJS (or Touch, if you're making a mobile app) as a static resource.  It's big, so if you don't filter out most of the files from the Sencha download you'll end up with a resource that exceeds the size limit.  I kept the top-level .js files (including useful debug variants), the resources necessary for my client code (especially styles and icon images), and some useful bits of the "examples" directory.  You may need to experiment to get it right.

For the 4.0.2a release I removed every subdirectory except "resources" and one subdirectory under examples, "examples/shared/icons".  I think there are useful icons other than just the above three, so it's worth preserving them for other code.

This code has been most recently tested with ExtJS 4.1.1 and the Summer '12 update of Salesforce.com.

