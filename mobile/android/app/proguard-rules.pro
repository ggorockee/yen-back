# WorkManager (pulled in by Google Mobile Ads) creates its Room database via
# reflection: Class.forName("...WorkDatabase_Impl").newInstance(). Room 2.2.x's
# consumer rule keeps the class but, under R8 full mode, not its no-arg
# constructor, so release builds crashed at startup with
# "Failed to create an instance of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
