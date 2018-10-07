rule wgc1_prepare:
    input:
        lambda w: config['wgc']['genomes'][w.genome]['assembly']
    output:
        fna = "%s/{genome}/10_genome.fna" % config['wgc']['dirg'],
        size = "%s/{genome}/15_intervals/01.chrom.sizes" % config['wgc']['dirg'],
    params:
        odir = lambda w: "%s/%s" % (config['wgc']['dirg'], w.genome),
        cdir = lambda w: "%s/%s/11_chroms" % (config['wgc']['dirg'], w.genome),
        extra = config['wgc']['prepare']['extra']
    threads:
        config['wgc']['prepare']['threads']
    shell:
        """
        mkdir -p {params.odir}
        cp -fL {input} {output.fna}
        genome fasta {params.odir}
        genome blat {params.odir}
        """

rule wgc1_break_tgt:
    input:
        "%s/{genome}/10_genome.fna" % config['wgc']['dirg']
    output:
        expand("%s/{{genome}}/11_chroms/{tchrom}.fa" % config['wgc']['dirg'], \
                tchrom = config['wgc']['genomes']['B73']['chroms'].split())
    params:
        odir = lambda w: "%s/%s" % (config['wgc']['dirg'], w.genome),
        cdir = lambda w: "%s/%s/11_chroms" % (config['wgc']['dirg'], w.genome),
    shell:
        """
        mkdir -p {params.cdir}
        faSplit byname {input} {params.cdir}/
        """

rule wgc1_break_qry:
    input:
        "%s/{genome}/10_genome.fna" % config['wgc']['dirg']
    output:
        fnas = expand("%s/{{genome}}/87_qrys/part.{idx}.fna" % \
                config['wgc']['dirg'], 
                idx = range(1,config['wgc']['npieces']+1)),
        chain = "%s/{genome}/86.chain" % config['wgc']['dirg'],
    params:
        odir = lambda w: "%s/%s" % (config['wgc']['dirg'], w.genome),
        cdir = lambda w: "%s/%s/11_chroms" % (config['wgc']['dirg'], w.genome),
        npieces = config['wgc']['npieces'],
    shell:
        """
        bed filter -min 5000 {params.odir}/15_intervals/11.gap.bed \
                > {params.odir}/81.qry.gap.bed
        subtractBed -nonamecheck -a {params.odir}/15_intervals/01.chrom.bed \
                -b {params.odir}/81.qry.gap.bed | bed filter -min 100 - | \
                bed makewindow -w 1000000 -s 995000 - \
                > {params.odir}/85.qry.clean.bed
        bed size {params.odir}/85.qry.clean.bed
        faSplit.R {params.odir}/85.qry.clean.bed {params.odir}/10_genome.fna \
                {params.odir}/15_intervals/01.chrom.sizes \
                {params.odir}/87_qrys \
                --chain {params.odir}/86.chain -n {params.npieces}
        """

rule wgc2_align:
    input:
        tgt = "%s/{tgt}/11_chroms/{tchrom}.fa" % config['wgc']['dirg'],
        qry = "%s/{qry}/87_qrys/part.{idx}.fna" % config['wgc']['dirg'],
    output:
        "%s/{qry}_{tgt}/q{idx}.{tchrom}.psl" % config['wgc']['dira']
    params:
        sam = "%s/{qry}_{tgt}/q{idx}.{tchrom}.sam" % config['wgc']['dira'],
        lav = "%s/{qry}_{tgt}/q{idx}.{tchrom}.lav" % config['wgc']['dira'],
        extra = config['wgc']['align']['extra']
    threads:
        config['wgc']['align']['threads']
    shell:
        """
        minimap2 -x asm20 -a -t {threads} \
                {input.tgt} {input.qry} | \
                sam2psl.py -i - -o {output}
        """
        #lastz {input.tgt} {input.qry} \
        #        --show=defaults --progress \
        #        --gfextend --gapped --inner=1000 --format=lav > {params.lav}
        #lavToPsl {params.lav} {output}
        #pblat {input.tgt_bit} {input.qry} -threads={threads} \
        #        -ooc={input.tgt_ooc} {output}
        #rm {params.lav}

rule wgc3_merge:
    input:
        expand("%s/{{qry}}_{{tgt}}/q{idx}.{tchrom}.psl" % \
                config['wgc']['dira'], \
                idx = range(1,config['wgc']['npieces']+1), \
                tchrom = config['wgc']['genomes']['B73']['chroms'].split())
    output:
        "%s/{qry}_{tgt}/02.coord.psl" % config['wgc']['dirc']
    params:
        odir = lambda w: "%s/%s_%s" % (config['wgc']['dirc'], w.qry, w.tgt),
        chain = lambda w: "%s/%s/86.chain" %
            (config['wgc']['dirg'], w.qry),
        tbit = lambda w: "%s/%s/21_dbs/blat/db.2bit" % 
            (config['wgc']['dirg'], w.tgt),
        qbit = lambda w: "%s/%s/21_dbs/blat/db.2bit" %
            (config['wgc']['dirg'], w.qry),
        tsize = lambda w: "%s/%s/15_intervals/01.chrom.sizes" % 
            (config['wgc']['dirg'], w.tgt),
        qsize = lambda w: "%s/%s/15_intervals/01.chrom.sizes" % 
            (config['wgc']['dirg'], w.qry),
        extra = config['wgc']['merge']['extra']
    threads:
        config['wgc']['merge']['threads']
    shell:
        """
        mkdir -p {params.odir}
        pslCat -nohead {input} > {params.odir}/01.psl
        psl coordQ {params.odir}/01.psl {params.qsize} \
                >{params.odir}/02.coord.psl
        pslCheck {params.odir}/02.coord.psl
        """
        #pslSwap {params.odir}/01.psl {params.odir}/02.swap.psl
        #liftOver -pslT {params.odir}/02.swap.psl {params.chain} \
        #        {params.odir}/03.swap.coord.psl {params.odir}/unMapped
        #pslCheck -querySizes={params.qsize} -targetSizes={params.tsize} \
        #        {params.odir}/04.psl \
        #        -pass={params.odir}/05.pass.psl \
        #        -fail={params.odir}/05.fail.psl

rule wgc4_chain:
    input:
         "%s/{qry}_{tgt}/02.coord.psl" % config['wgc']['dirc']
    output:
         "%s/{qry}_{tgt}/23.chain" % config['wgc']['dirc']
    params:
        odir = lambda w: "%s/%s_%s" % (config['wgc']['dirc'], w.qry, w.tgt),
        tbit = lambda w: "%s/%s/21_dbs/blat/db.2bit" % 
            (config['wgc']['dirg'], w.tgt),
        qbit = lambda w: "%s/%s/21_dbs/blat/db.2bit" %
            (config['wgc']['dirg'], w.qry),
        tsize = lambda w: "%s/%s/15_intervals/01.chrom.sizes" % 
            (config['wgc']['dirg'], w.tgt),
        qsize = lambda w: "%s/%s/15_intervals/01.chrom.sizes" % 
            (config['wgc']['dirg'], w.qry),
        extra = config['wgc']['chain']['extra']
    threads:
        config['wgc']['chain']['threads']
    shell:
        """
        axtChain -linearGap=medium -psl {input} \
                {params.tbit} {params.qbit} {params.odir}/10.chain
        chainPreNet {params.odir}/10.chain {params.tsize} {params.qsize} \
                {params.odir}/11.chain
        chainSwap {params.odir}/11.chain {params.odir}/11.q.chain
        
        chainNet {params.odir}/11.chain {params.tsize} {params.qsize} \
                {params.odir}/13.t.net {params.odir}/13.q.net
        netChainSubset {params.odir}/13.t.net {params.odir}/11.chain stdout | \
                chainSort stdin {params.odir}/13.t.chain
        netChainSubset {params.odir}/13.q.net {params.odir}/11.q.chain stdout | \
                chainSort stdin {params.odir}/13.q.chain
        chainNet {params.odir}/13.q.chain {params.qsize} {params.tsize} \
                /dev/null {params.odir}/15.net
        netChainSubset {params.odir}/15.net {params.odir}/11.chain \
                {params.odir}/15.chain
        """
        #chainSwap 31.3.chain 31.3.q.chain