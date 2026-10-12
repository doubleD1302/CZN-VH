# Classes instantiated through Room, WorkManager, Shizuku and XXHash reflection.
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class vn.czn.viethoa.czn_patcher.UpdateWorker { *; }
-keep class vn.czn.viethoa.czn_patcher.PatchUserService { *; }
-keep class net.jpountz.** { *; }
