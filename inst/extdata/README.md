# Example data of condathis

Small files for the examples, the vignette and the tests of `condathis`.
Get the path of a file with
`system.file("extdata", "<file name>", package = "condathis")`.

## `example.bam`

A BAM file (1.8 KB) with the header of a human hg19 alignment (`@SQ`
lines for chr1 to chr22, chrM and chrX) and 25 alignments: single reads of
27 bases at the start of chr1, from position 10,156.

- Source: the ENCODE project, University of Washington Repli-seq of K562
  cells, `wgEncodeUwRepliSeqK562S2AlnRep1.bam`
  (<https://hgdownload.soe.ucsc.edu/goldenPath/hg19/encodeDCC/wgEncodeUwRepliSeq/>).
  Its `@PG` lines name that file and the `samtools view` calls that
  converted it.
- Used by: the vignette *Introduction to condathis*
  (`vignettes/condathis.qmd`), which runs `samtools view -H` on it.
- Terms: ENCODE data can be downloaded, analyzed and published "without
  restrictions" (<https://www.encodeproject.org/help/citing-encode/>).

## `sample1_L001_R1_001.fastq.gz`, `sample1_L001_R2_001.fastq.gz`, `sample2_L001_R1_001.fastq.gz`, `sample2_L001_R2_001.fastq.gz`

Paired-end FASTQ files of two samples, named as Illumina `bcl2fastq`
names its output (`R1` and `R2` are the two mates of each read). Each read
has 100 bases. `sample1` has 1,086 read pairs and `sample2` has 1,145.
Every base quality is `#`, a placeholder.

The read names, such as
`read1/gi|424037187|ref|NR_073460.1| Homo sapiens ...;mate1:370-469;mate2:537-635`,
name the transcript a read comes from and the positions of both mates on
it. This is how the polyester Bioconductor package names the reads that
it simulates, so these are simulated reads, not sequencing data. They come
from 20 human RefSeq transcripts, of genes on chromosome 22 such as XKR3,
IL17RA and CECR1.

- Used by: `sample1_L001_R1_001.fastq.gz` in the examples of `run()` and
  `run_pipeline()` and in the `fastqc` example of the README. The other
  three files are not used by `condathis` itself. They are kept as a
  complete paired-end example, as shipped since `condathis` 0.1.0.
- License: distributed under the license of `condathis` (MIT).

## `stat-env.yml`

A Conda environment file for an environment named `stats`, with `numpy`
and `pandas` and no channels, so `create_env()` uses its `channels`
argument.

- Used by: the test "Create conda env from file"
  (`tests/testthat/test-create_env.R`), through `env_file`.
- License: written for `condathis`, distributed under its license (MIT).

## `polyglot-channel/`

A local Conda channel with one package, `polyglot` 0.1.0 (1.5 KB), a
script that runs on Linux, macOS and Windows. See
`polyglot-channel/README.md` for its contents and its source,
<https://github.com/luciorq/polyglot>.

- Used by: the examples of the help pages that create environments or run
  commands, such as `create_env()`, `run()` and `validate_env()`, and the
  tests (`tests/testthat/helper-polyglot.R`).
- License: `polyglot` is the work of the maintainer of `condathis`, who
  distributes it here under the license of `condathis` (MIT).
