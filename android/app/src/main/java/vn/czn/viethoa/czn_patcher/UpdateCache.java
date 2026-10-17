package vn.czn.viethoa.czn_patcher;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.util.*;

/** Only disposable app-private downloads. Never traverses game files or backups. */
public final class UpdateCache {
    private static final Map<String, Integer> ACTIVE = new HashMap<>();
    private UpdateCache() {}

    public static File directory(File filesDir) throws IOException {
        File root = filesDir.getCanonicalFile();
        File dir = new File(root, "updates");
        if (Files.isSymbolicLink(dir.toPath()) || !root.equals(dir.getCanonicalFile().getParentFile()))
            throw new IOException("Thư mục cập nhật không hợp lệ.");
        if (!dir.isDirectory() && !dir.mkdirs() && !dir.isDirectory())
            throw new IOException("Không tạo được bộ nhớ cập nhật.");
        return dir;
    }

    /** Ref-counted because the worker and foreground can use the same artifact. */
    public static synchronized Lease acquire(File... files) throws IOException {
        List<String> paths = new ArrayList<>();
        for (File file : files) paths.add(file.getCanonicalPath());
        for (String path : paths) ACTIVE.put(path, ACTIVE.getOrDefault(path, 0) + 1);
        return new Lease(paths);
    }

    public static final class Lease implements AutoCloseable {
        private final List<String> paths;
        private boolean closed;
        private Lease(List<String> paths) { this.paths = paths; }
        @Override public void close() {
            synchronized (UpdateCache.class) {
                if (closed) return;
                closed = true;
                for (String path : paths) {
                    int remaining = ACTIVE.get(path) - 1;
                    if (remaining == 0) ACTIVE.remove(path); else ACTIVE.put(path, remaining);
                }
            }
        }
    }

    private static boolean active(File file) throws IOException {
        return ACTIVE.containsKey(file.getCanonicalPath());
    }
    private static boolean directFile(File dir, File file) throws IOException {
        return Files.isRegularFile(file.toPath(), LinkOption.NOFOLLOW_LINKS)
            && dir.getCanonicalFile().equals(file.getCanonicalFile().getParentFile());
    }
    public static boolean apkName(String name) { return name.matches("[a-f0-9]{64}\\.apk"); }
    public static boolean installerLeaseValid(long installedCode,long candidateCode,long until,long now) {
        return candidateCode>installedCode && until>now && until-now<=86400000L;
    }
    private static boolean patchName(String name) { return name.matches("[a-f0-9]{64}\\.cznpatch"); }
    private static boolean partialName(String name) {
        return name.matches("[a-f0-9]{64}\\.part-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}");
    }
    private static File newest(List<File> files, String preferred) {
        for (File file : files) if (file.getName().equals(preferred)) return file;
        return files.stream().max(Comparator.comparingLong(File::lastModified)
            .thenComparing(File::getName)).orElse(null);
    }

    /** usefulApks are archive versions newer than the installed app, checked by the caller. */
    public static synchronized long prune(File filesDir, File cacheDir, String preferredApk,
            String preferredPatch, Set<String> usefulApks, Set<String> installerApks) throws IOException {
        File dir = directory(filesDir);
        File[] entries = dir.listFiles();
        if (entries == null) throw new IOException("Không đọc được bộ nhớ cập nhật.");
        List<File> apks = new ArrayList<>(), patches = new ArrayList<>();
        for (File file : entries) if (directFile(dir, file)) {
            if (apkName(file.getName()) && usefulApks.contains(file.getName())) apks.add(file);
            if (patchName(file.getName())) patches.add(file);
        }
        File app = newest(apks, preferredApk), patch = newest(patches, preferredPatch);
        long removed = 0;
        for (File file : entries) {
            if (!directFile(dir, file) || active(file)) continue;
            String name = file.getName();
            boolean obsolete = partialName(name)
                || (apkName(name) && !file.equals(app) && !installerApks.contains(name))
                || (patchName(name) && !file.equals(patch));
            if (obsolete) { long size = file.length(); if (file.delete()) removed += size; }
        }
        // Old versions copied the bundled ZIP to filesDir on every install.
        removed += removeDisposable(filesDir, new File(filesDir, "bundled.cznpatch"));
        if (!Files.isSymbolicLink(cacheDir.toPath())) {
            File[] temp = cacheDir.listFiles();
            if (temp != null) for (File file : temp)
                if (file.getName().matches("bundled-[a-f0-9-]{36}\\.cznpatch"))
                    removed += removeDisposable(cacheDir, file);
        }
        return removed;
    }

    private static long removeDisposable(File dir, File file) throws IOException {
        if (!directFile(dir, file) || active(file)) return 0;
        long size = file.length();
        return file.delete() ? size : 0;
    }
}
