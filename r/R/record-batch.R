# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

#' @include arrow-package.R
#' @include array.R
#' @title RecordBatch class
#' @description A record batch is a collection of equal-length arrays matching
#' a particular [Schema]. It is a table-like data structure that is semantically
#' a sequence of [fields][Field], each a contiguous Arrow [Array].
#' @usage NULL
#' @format NULL
#' @docType class
#'
#' @section S3 Methods and Usage:
#' Record batches are data-frame-like, and many methods you expect to work on
#' a `data.frame` are implemented for `RecordBatch`. This includes `[`, `[[`,
#' `$`, `names`, `dim`, `nrow`, `ncol`, `head`, and `tail`. You can also pull
#' the data from an Arrow record batch into R with `as.data.frame()`. See the
#' examples.
#'
#' A caveat about the `$` method: because `RecordBatch` is an `R6` object,
#' `$` is also used to access the object's methods (see below). Methods take
#' precedence over the table's columns. So, `batch$Slice` would return the
#' "Slice" method function even if there were a column in the table called
#' "Slice".
#'
#' A caveat about the `[` method for row operations: only "slicing" is
#' currently supported. That is, you can select a continuous range of rows
#' from the table, but you can't filter with a `logical` vector or take an
#' arbitrary selection of rows by integer indices.
#'
#' @section R6 Methods:
#' In addition to the more R-friendly S3 methods, a `RecordBatch` object has
#' the following R6 methods that map onto the underlying C++ methods:
#'
#' - `$Equals(other)`: Returns `TRUE` if the `other` record batch is equal
#' - `$column(i)`: Extract an `Array` by integer position from the batch
#' - `$column_name(i)`: Get a column's name by integer position
#' - `$names()`: Get all column names (called by `names(batch)`)
#' - `$GetColumnByName(name)`: Extract an `Array` by string name
#' - `$RemoveColumn(i)`: Drops a column from the batch by integer position
#' - `$select(spec)`: Return a new record batch with a selection of columns.
#'    This supports the usual `character`, `numeric`, and `logical` selection
#'    methods as well as "tidy select" expressions.
#' - `$Slice(offset, length = NULL)`: Create a zero-copy view starting at the
#'    indicated integer offset and going for the given length, or to the end
#'    of the table if `NULL`, the default.
#' - `$Take(i)`: return an `RecordBatch` with rows at positions given by
#'    integers (R vector or Array Array) `i`.
#' - `$Filter(i)`: return an `RecordBatch` with rows at positions where logical
#'    vector (or Arrow boolean Array) `i` is `TRUE`.
#' - `$serialize()`: Returns a raw vector suitable for interprocess communication
#' - `$cast(target_schema, safe = TRUE, options = cast_options(safe))`: Alter
#'    the schema of the record batch.
#'
#' There are also some active bindings
#' - `$num_columns`
#' - `$num_rows`
#' - `$schema`
#' - `$columns`: Returns a list of `Array`s
#' @rdname RecordBatch
#' @name RecordBatch
RecordBatch <- R6Class("RecordBatch", inherit = ArrowObject,
  public = list(
    column = function(i) shared_ptr(Array, RecordBatch__column(self, i)),
    column_name = function(i) RecordBatch__column_name(self, i),
    names = function() RecordBatch__names(self),
    Equals = function(other, ...) {
      # RecordBatch->Equals should have a check_metadata arg
      # https://issues.apache.org/jira/browse/ARROW-7891
      inherits(other, "RecordBatch") && RecordBatch__Equals(self, other)
    },
    GetColumnByName = function(name) {
      assert_is(name, "character")
      assert_that(length(name) == 1)
      shared_ptr(Array, RecordBatch__GetColumnByName(self, name))
    },
    select = function(spec) {
      spec <- enquo(spec)
      if (quo_is_null(spec)) {
        self
      } else {
        all_vars <- self$names()
        vars <- vars_select(all_vars, !!spec)
        indices <- match(vars, all_vars)
        shared_ptr(RecordBatch, RecordBatch__select(self, indices))
      }
    },
    RemoveColumn = function(i){
      shared_ptr(RecordBatch, RecordBatch__RemoveColumn(self, i))
    },

    Slice = function(offset, length = NULL) {
      if (is.null(length)) {
        shared_ptr(RecordBatch, RecordBatch__Slice1(self, offset))
      } else {
        shared_ptr(RecordBatch, RecordBatch__Slice2(self, offset, length))
      }
    },
    Take = function(i) {
      if (is.numeric(i)) {
        i <- as.integer(i)
      }
      if (is.integer(i)) {
        i <- Array$create(i)
      }
      assert_is(i, "Array")
      shared_ptr(RecordBatch, RecordBatch__Take(self, i))
    },
    Filter = function(i) {
      if (is.logical(i)) {
        i <- Array$create(i)
      }
      assert_is(i, "Array")
      shared_ptr(RecordBatch, RecordBatch__Filter(self, i))
    },
    serialize = function() ipc___SerializeRecordBatch__Raw(self),
    ToString = function() ToString_tabular(self),

    cast = function(target_schema, safe = TRUE, options = cast_options(safe)) {
      assert_is(target_schema, "Schema")
      assert_is(options, "CastOptions")
      assert_that(identical(self$schema$names, target_schema$names), msg = "incompatible schemas")
      shared_ptr(RecordBatch, RecordBatch__cast(self, target_schema, options))
    }
  ),

  active = list(
    num_columns = function() RecordBatch__num_columns(self),
    num_rows = function() RecordBatch__num_rows(self),
    schema = function() shared_ptr(Schema, RecordBatch__schema(self)),
    columns = function() map(RecordBatch__columns(self), shared_ptr, Array)
  )
)

RecordBatch$create <- function(..., schema = NULL){
  arrays <- list2(...)
  # making sure there are always names
  if (is.null(names(arrays))) {
    names(arrays) <- rep_len("", length(arrays))
  }
  stopifnot(length(arrays) > 0)
  shared_ptr(RecordBatch, RecordBatch__from_arrays(schema, arrays))
}

#' @param ... A `data.frame` or a named set of Arrays or vectors. If given a
#' mixture of data.frames and vectors, the inputs will be autospliced together
#' (see examples).
#' @param schema a [Schema], or `NULL` (the default) to infer the schema from
#' the data in `...`
#' @rdname RecordBatch
#' @examples
#' \donttest{
#' batch <- record_batch(name = rownames(mtcars), mtcars)
#' dim(batch)
#' dim(head(batch))
#' names(batch)
#' batch$mpg
#' batch[["cyl"]]
#' as.data.frame(batch[4:8, c("gear", "hp", "wt")])
#' }
#' @export
record_batch <- RecordBatch$create

#' @export
names.RecordBatch <- function(x) {
  x$names()
}

#' @importFrom methods as
#' @export
`[.RecordBatch` <- function(x, i, j, ..., drop = FALSE) {
  if (!missing(j)) {
    # Selecting columns is cheaper than filtering rows, so do it first.
    # That way, if we're filtering too, we have fewer arrays to filter/slice/take
    x <- x$select(j)
    if (drop && ncol(x) == 1L) {
      x <- x$column(0)
    }
  }
  if (!missing(i)) {
    x <- filter_rows(x, i, ...)
  }
  x
}

#' @export
`[[.RecordBatch` <- function(x, i, ...) {
  if (is.character(i)) {
    x$GetColumnByName(i)
  } else if (is.numeric(i)) {
    x$column(i - 1)
  } else {
    stop("'i' must be character or numeric, not ", class(i), call. = FALSE)
  }
}

#' @export
`$.RecordBatch` <- function(x, name, ...) {
  assert_is(name, "character")
  assert_that(length(name) == 1L)
  if (name %in% ls(x)) {
    get(name, x)
  } else {
    x$GetColumnByName(name)
  }
}

#' @export
dim.RecordBatch <- function(x) {
  c(x$num_rows, x$num_columns)
}

#' @export
as.data.frame.RecordBatch <- function(x, row.names = NULL, optional = FALSE, use_threads = TRUE, ...){
  RecordBatch__to_dataframe(x, use_threads = option_use_threads())
}

#' @export
head.RecordBatch <- head.Array

#' @export
tail.RecordBatch <- tail.Array

ToString_tabular <- function(x, ...) {
  # Generic to work with both RecordBatch and Table
  sch <- unlist(strsplit(x$schema$ToString(), "\n"))
  sch <- sub("(.*): (.*)", "$\\1 <\\2>", sch)
  dims <- sprintf("%s rows x %s columns", nrow(x), ncol(x))
  paste(c(dims, sch), collapse = "\n")
}
