# Project-specific R8 rules. Flutter and most plugins ship their own; these cover what they miss.

# The ads SDK brings in WorkManager, which is started at process launch by
# androidx.startup and creates its Room database by reflection
# (Class.forName("...WorkDatabase_Impl").newInstance()). R8 kept the class but removed the
# constructor it could not see being called, and the app crashed before its first frame:
#   "Failed to create an instance of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(...); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# Workers and startup initializers are also created by class name.
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-keep class * implements androidx.startup.Initializer { <init>(); }

-dontwarn com.google.android.play.core.**
