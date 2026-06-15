Hi,

The app only ever reads the Settings record, it never writes to it, so it couldn't have removed anything. And the access code is built into the app itself, so it works whether or not it's in CloudKit.

- defaultLatitude, defaultLongitude, and the passcode are all optional override fields.

The app reads them when they're present, but falls back to built-in defaults when they're absent. the SLAC coordinate we agreed on for the fallback location, and 4299 for the access code. Because the app only reads them, it never creates them in CloudKit; they appear in this view only if they were typed onto the record by hand. In this Development environment they aren't currently on the record (they may have been there briefly and then cleared — an environment reset would do it), which is why you only see the two dosimeter-length fields.

So the access-code requirement is satisfied today: 4299 is hard-coded as the default, and the CloudKit field exists only so you can change the code later without an app update. You don't need to add anything for 4299 to work.

If you'd like CloudKit control over any of them, you can add them to the Settings record:

1. Click the Settings record (009AE09D-…) to open it.

2. Add three fields, with these exact names and types:
    - defaultLatitude — Double — e.g. 37.41927542738301
    - defaultLongitude — Double — e.g. -122.20517033784913
    - superUserPasscode — Int (Int64) — e.g. 4299, or a new code

3. Save the record. In Development that adds them to the schema automatically;
for Production we'd deploy the schema change first.

The app is running on the built-in defaults right now. Add those three fields only if you want to override the fallback coordinate or rotate the access code from CloudKit.

Daniel
