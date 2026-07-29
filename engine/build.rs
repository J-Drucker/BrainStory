use std::path::PathBuf;

fn main() {
    let root = PathBuf::from("vendor/libeep");
    let source_root = root.join("src");
    let sources = [
        "libavr/avr.c",
        "libavr/avrcfg.c",
        "libcnt/cnt.c",
        "libcnt/cntutils.c",
        "libcnt/evt.c",
        "libcnt/raw3.c",
        "libcnt/rej.c",
        "libcnt/riff64.c",
        "libcnt/riff.c",
        "libcnt/seg.c",
        "libcnt/trg.c",
        "libeep/eepio.c",
        "libeep/eepmem.c",
        "libeep/eepmisc.c",
        "libeep/eepraw.c",
        "libeep/val.c",
        "libeep/var_string.c",
        "v4/eep.c",
    ];

    let mut build = cc::Build::new();
    build
        .include(&source_root)
        .define("LIBEEP_VERSION_MAJOR", "3")
        .define("LIBEEP_VERSION_MINOR", "3")
        .define("LIBEEP_VERSION_PATCH", "179")
        .warnings(false);
    for source in sources {
        build.file(source_root.join(source));
    }
    if cfg!(target_os = "windows") {
        build.define("WIN32", None);
    }
    build.compile("libeep");

    println!("cargo:rerun-if-changed={}", root.display());
}
