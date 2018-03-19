/*
 * Copyright 2017 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "Firestore/Source/Local/FSTMemoryRemoteDocumentCache.h"

#import "Firestore/Source/Core/FSTQuery.h"
#import "Firestore/Source/Local/FSTMutationQueue.h"
#import "Firestore/Source/Local/FSTQueryCache.h"
#import "Firestore/Source/Model/FSTDocument.h"
#import "Firestore/Source/Model/FSTDocumentDictionary.h"
#import "Firestore/Source/Model/FSTDocumentKey.h"

NS_ASSUME_NONNULL_BEGIN

@interface FSTMemoryRemoteDocumentCache ()

/** Underlying cache of documents. */
@property(nonatomic, strong) FSTMaybeDocumentDictionary *docs;

@end

@implementation FSTMemoryRemoteDocumentCache

- (instancetype)init {
  if (self = [super init]) {
    _docs = [FSTMaybeDocumentDictionary maybeDocumentDictionary];
  }
  return self;
}

- (void)shutdown {
}

- (void)addEntry:(FSTMaybeDocument *)document group:(FSTWriteGroup *)group {
  self.docs = [self.docs dictionaryBySettingObject:document forKey:document.key];
}

- (void)removeEntryForKey:(FSTDocumentKey *)key group:(FSTWriteGroup *)group {
  self.docs = [self.docs dictionaryByRemovingObjectForKey:key];
}

- (nullable FSTMaybeDocument *)entryForKey:(FSTDocumentKey *)key {
  return self.docs[key];
}

- (FSTDocumentDictionary *)documentsMatchingQuery:(FSTQuery *)query {
  FSTDocumentDictionary *result = [FSTDocumentDictionary documentDictionary];

  // Documents are ordered by key, so we can use a prefix scan to narrow down the documents
  // we need to match the query against.
  FSTDocumentKey *prefix = [FSTDocumentKey keyWithPath:query.path.Append("")];
  NSEnumerator<FSTDocumentKey *> *enumerator = [self.docs keyEnumeratorFrom:prefix];
  for (FSTDocumentKey *key in enumerator) {
    if (!query.path.IsPrefixOf(key.path)) {
      break;
    }
    FSTMaybeDocument *maybeDoc = self.docs[key];
    if (![maybeDoc isKindOfClass:[FSTDocument class]]) {
      continue;
    }
    FSTDocument *doc = (FSTDocument *)maybeDoc;
    if ([query matchesDocument:doc]) {
      result = [result dictionaryBySettingObject:doc forKey:doc.key];
    }
  }

  return result;
}

- (NSUInteger)removeOrphanedDocuments:(id<FSTQueryCache>)queryCache
                throughSequenceNumber:(FSTListenSequenceNumber)upperBound
                        mutationQueue:(id<FSTMutationQueue>)mutationQueue
                                group:(FSTWriteGroup *)group {
  NSUInteger count = 0;
  FSTMaybeDocumentDictionary *updatedDocs = self.docs;
  for (FSTDocumentKey *docKey in [self.docs keyEnumerator]) {
    if ([mutationQueue containsKey:docKey] || [queryCache containsKey:docKey]) {
      continue;
    }
    // TODO(gsoltis): the following line needs a sequence number guard
    if ([queryCache removeOrphanedDocument:docKey upperBound:upperBound group:group]) {
      updatedDocs = [updatedDocs dictionaryByRemovingObjectForKey:docKey];
      NSLog(@"Removing %@", docKey);
      count++;
    }
  }
  self.docs = updatedDocs;
  return count;
}

- (long)byteSize {
  __block long result = 0;
  [self.docs enumerateKeysAndObjectsUsingBlock:^(FSTDocumentKey *key, FSTMaybeDocument *value, BOOL *stop) {

  }];
}

@end

NS_ASSUME_NONNULL_END
