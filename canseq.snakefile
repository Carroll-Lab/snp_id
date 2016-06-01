from Bio import SeqIO

def parse_var_file(varscan_file):
    """
    parses varscan file
    returns list of tuples with snp details
    """
    var_list=[]
    with open(varscan_file, 'r') as f:
        for line in f:
            if line[:5]=='Chrom':
                pass
            else:
                snp_line = line.split('\t',5)
                snp_pos = int(snp_line[1])
                snp_ref = snp_line[2]
                snp_var = snp_line[3]
                freq_var = snp_line[4].split(':')[4]
                result = (snp_pos, snp_ref, snp_var, freq_var)
                var_list.append(result)
    f.close()
    return var_list

def mod_gb(var_list, gb_in_file, gb_out_file):
    """
    parses gb_in_file
    inserts carscan SNP infor
    writes to new gb_out_file
    """
    insert_pos=False
    with open(gb_in_file, 'r') as f:
        with open (gb_out_file, 'w') as g:
            for line in f:
                if insert_pos:

                    for var in var_list:
                        g.write('     misc_feature     {0}..{0}\n'.format(str(var[0])))
                        g.write('                     /vntifkey="21"\n')
                        g.write('                     /label={0}-->{1}_{2}\n'.format(var[1], var[2], var[3]))
                    insert_pos=False
                    g.write(line)
                elif line[:8]=="FEATURES":
                    insert_pos=True
                    g.write(line)
                else:
                    g.write(line)
    g.close()
    f.close()


IDS, = glob_wildcards("raw/{smp}_1.fq")
gbs, = glob_wildcards("gb/{gb}.gb")

rule alignments:
	input: 
		expand("annot_gb/{smp}.{fa}.gb", smp=IDS, fa=gbs)

rule trimming:
	input:
		fwd="raw/{smp}_1.fq", 
		rev="raw/{smp}_2.fq"
	output:
		fwd="seq/{smp}_1.fq",
		rvs="seq/{smp}_2.fq",
		fwd_u="seq/{smp}_1_U.fq",
		rvs_u="seq/{smp}_2_U.fq"
	shell:
		"trimmomatic PE -threads 4 {input.fwd} {input.rev} {output.fwd} {output.fwd_u} {output.rvs} {output.rvs_u} ILLUMINACLIP:TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36"

rule converting_gb:
	input:
		ingb="gb/{fa}.gb"

	output: 
		outfa="fa/{fa}.fa"
	run:
		SeqIO.convert(input.ingb, "gb", output.outfa, "fasta"),
		shell("bowtie2-build -f {output.outfa} {output.outfa}")

rule align:
	input:
		index = "fa/{fa}.fa",
		fwd = "seq/{smp}_1.fq",
		rvs = "seq/{smp}_2.fq",
	output:
		out_align = "align/{smp}.{fa}.bam"
	threads: 12
	shell:
		"bowtie2 -x {input.index} -p {threads} -1 {input.fwd} -2 {input.rvs} | samtools view -@ {threads} -bS - | samtools sort -@ {threads} - > {output.out_align}"

rule snp_id:
	input:
		fasta = "fa/{fa}.fa",
		alignment = "align/{smp}.{fa}.bam"
	output:
		csv_file = "snp/{smp}.{fa}.csv"
	shell:
		"samtools mpileup -f {input.fasta} {input.alignment}  | varscan mpileup2snp --min-var-freq 0.0075 --min-coverage 200 --min-reads2 30 > {output.csv_file}"

rule gb_annot:
	input:
		csv_file = "snp/{smp}.{fa}.csv",
		ingb = "gb/{fa}.gb"
	output:
		outgb = "annot_gb/{smp}.{fa}.gb"
	run:
		var_list = parse_var_file(input.csv_file)
		mod_gb(var_list,input.ingb, output.outgb)




