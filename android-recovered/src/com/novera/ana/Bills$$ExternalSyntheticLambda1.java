package com.novera.ana;

import com.novera.ana.BillCore;

/* compiled from: D8$$SyntheticClass */
/* loaded from: classes.dex */
public final /* synthetic */ class Bills$$ExternalSyntheticLambda1 implements BillCore.Signer {
    @Override // com.novera.ana.BillCore.Signer
    public final byte[][] sign(byte[] bArr) {
        return Flex.signRaw(bArr);
    }
}
